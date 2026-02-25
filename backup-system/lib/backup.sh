#!/bin/bash
# Core backup logic.
# Depends on globals set by core.sh: DEST_REMOTE, DEST_PATH, BACKUP_ROOT,
# RCLONE_CONFIG, RCLONE_OPTIONS, LOG_DIR, DEBUG, CONFIG_FILE.

# Build the full rclone destination path for a given type and source name.
# This is the single source of truth for path construction — both backup_exists()
# and run_source_backup() call this function to guarantee consistency.
#
# $1: type        — monthly | quarterly
# $2: source_name — the .name field from config
# stdout: full rclone remote path
build_dest_path() {
    local type="$1"
    local source_name="$2"
    local year month quarter
    year=$(date +%Y)
    month=$(date +%m)
    quarter=$(( (10#$month - 1) / 3 + 1 ))

    case "$type" in
        monthly)
            echo "${DEST_REMOTE}:${DEST_PATH}/${BACKUP_ROOT}/${year}/monthly/${month}/${source_name}"
            ;;
        quarterly)
            echo "${DEST_REMOTE}:${DEST_PATH}/${BACKUP_ROOT}//${year}/quarterly/Q${quarter}/${source_name}"
            ;;
        *)
            log_error "build_dest_path: unknown type '$type'"
            return 1
            ;;
    esac
}

# Emit one compact JSON object per line for each backup source matching the given type.
# Uses yq + jq — no manual string splitting.
#
# $1: type — monthly | quarterly
# stdout: newline-separated compact JSON objects
# return 0: at least one source emitted; return 1: none found
parse_sources() {
    local type="$1"
    local output
    output=$(
        yq -o json '.backup_sources[]' "$CONFIG_FILE" \
            | jq -c --arg t "$type" 'select(.frequency == $t or .frequency == "both")'
    )
    if [[ -z "$output" ]]; then
        log_warning "No backup sources found for frequency: $type"
        return 1
    fi
    echo "$output"
}

# Check whether a backup already exists for the current period using rclone lsd.
# Does not touch the local filesystem. Requires rclone connectivity to the destination.
#
# $1: type        — monthly | quarterly
# $2: source_name — .name from config
# return 0: directory exists; return 1: absent or unreachable
backup_exists() {
    local type="$1"
    local source_name="$2"
    local dest
    dest=$(build_dest_path "$type" "$source_name") || return 1
    if rclone lsd "$dest" --config="$RCLONE_CONFIG" &>/dev/null; then
        log_info "Backup already exists: $dest"
        return 0
    else
        log_debug "No backup found at: $dest"
        return 1
    fi
}

# Write an rclone filter file for a source to the given directory.
# If neither includes nor excludes are set, writes nothing and returns empty stdout.
#
# $1: source_json — compact JSON string
# $2: log_subdir  — directory to write the filter file into
# stdout: absolute path to the written filter file, or empty string
write_filter_file() {
    local source_json="$1"
    local log_subdir="$2"
    local has_inc has_exc
    has_inc=$(jq -r '.includes | length > 0' <<< "$source_json")
    has_exc=$(jq -r '.excludes | length > 0' <<< "$source_json")

    [[ "$has_inc" == "false" && "$has_exc" == "false" ]] && return 0

    local filter_file="${log_subdir}/$(date +%Y%m%d%H%M%S)-filter.tmp"

    if [[ "$has_inc" == "true" ]]; then
        jq -r '.includes[]' <<< "$source_json" | sed 's/^/+ /' >> "$filter_file"
        echo "- **" >> "$filter_file"
    fi
    if [[ "$has_exc" == "true" ]]; then
        jq -r '.excludes[]' <<< "$source_json" | sed 's/^/- /' >> "$filter_file"
    fi

    echo "$filter_file"
}

# Execute rclone sync for one source.
# Builds the command as a Bash array — no eval, no string interpolation of paths.
# Per-source logs go to LOG_DIR/{safe_source_name}/YYYYMMDD-{type}.log.
#
# $1: type        — monthly | quarterly
# $2: source_json — compact JSON string (one line from parse_sources output)
# return: rclone exit code
run_source_backup() {
    local type="$1"
    local source_json="$2"

    local source_name source_remote source_path
    source_name=$(jq -r   '.name'   <<< "$source_json")
    source_remote=$(jq -r '.remote' <<< "$source_json")
    source_path=$(jq -r   '.path'   <<< "$source_json")

    local src="${source_remote}${source_path}"
    local dest
    dest=$(build_dest_path "$type" "$source_name") || return 1

    # Per-source log directory (spaces replaced with underscores for filesystem safety)
    local safe_name="${source_name// /_}"
    local log_subdir="${LOG_DIR}/${safe_name}"
    mkdir -p "$log_subdir"
    local log_file="${log_subdir}/$(date +%Y%m%d)-${type}.log"

    local filter_file
    filter_file=$(write_filter_file "$source_json" "$log_subdir")

    # Split options string into array — safe word splitting on flag tokens
    local -a opts=()
    [[ -n "$RCLONE_OPTIONS" ]] && read -ra opts <<< "$RCLONE_OPTIONS"

    # Build the command array — no eval, no string building
    local -a cmd=(rclone sync "$src" "$dest" --config="$RCLONE_CONFIG")
    cmd+=("${opts[@]}")
    [[ -n "$filter_file" ]] && cmd+=(--filter-from="$filter_file")
    cmd+=(--log-file="$log_file")

    log_info "Starting $type backup: '$source_name'"
    log_info "  src:  $src"
    log_info "  dest: $dest"
    log_debug "Command: ${cmd[*]}"

    "${cmd[@]}"
    local rc=$?

    # Clean up filter file unless debug mode is on
    [[ -n "$filter_file" && "$DEBUG" != "true" ]] && rm -f "$filter_file"

    if [[ $rc -eq 0 ]]; then
        log_info "Completed: '$source_name' ($type)"
    else
        log_error "Failed (exit $rc): '$source_name' ($type)"
    fi

    return $rc
}

# Orchestrate all backups for one type.
# Uses process substitution (not a pipe) so overall_status is tracked correctly
# in the parent shell — this is the fix for the pipe-subshell status tracking bug.
#
# $1: type  — monthly | quarterly
# $2: force — 1 to bypass backup_exists, 0 or empty to check
# return 0: all sources succeeded or were skipped; return 1: one or more failed
run_backup() {
    local type="$1"
    local force="${2:-0}"
    local overall_status=0
    local count=0

    notify_backup_started "$type"

    while IFS= read -r source_json; do
        [[ -z "$source_json" ]] && continue
        (( count++ ))
        local source_name
        source_name=$(jq -r '.name' <<< "$source_json")

        if [[ "$force" -eq 1 ]] || ! backup_exists "$type" "$source_name"; then
            run_source_backup "$type" "$source_json" || overall_status=1
        else
            log_info "Skipping '$source_name' — backup exists (use --force to override)"
        fi
    done < <(parse_sources "$type")

    if [[ $count -eq 0 ]]; then
        log_warning "No sources found for frequency: $type"
    fi

    notify_backup_completed "$type" $overall_status
    return $overall_status
}
