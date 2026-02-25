#!/bin/bash

# Parse YAML backup sources for the specified frequency
parse_backup_sources() {
    local backup_type="$1"  # monthly, quarterly, or both
    local sources_json=""
    local sources_count=0

    # Use yq to extract sources for the specified frequency directly from the config file
    if [ "$backup_type" = "both" ]; then
        # For "both", we need all sources
        sources_json=$(yq eval '.BACKUP_SOURCES[] | select(.frequency == "both" or .frequency == "monthly" or .frequency == "quarterly")' "$CONFIG_FILE")
    else
        # For specific frequency, get matching sources or those marked as "both"
        sources_json=$(yq eval ".BACKUP_SOURCES[] | select(.frequency == \"$backup_type\" or .frequency == \"both\")" "$CONFIG_FILE")
    fi

    # Debug output after capturing the sources_json (redirected to stderr)
    log_debug "Sources for $backup_type:\n$sources_json" >&2

    # Process the YAML into proper JSON objects
    local cleaned_sources=""
    local current_source=""
    local in_source=false

    # Read the output line by line
    while IFS= read -r line; do
        # Skip log lines (those containing date/time stamps in brackets)
        if [[ "$line" =~ ^\[.*\] ]]; then
            continue
        fi

        # If this is a new source (starts with "name:")
        if [[ "$line" =~ ^name: ]]; then
            # If we already had a source in progress, add it to our output
            if [ "$in_source" = true ] && [ -n "$current_source" ]; then
                # Add JSON formatting
                current_source="{ $current_source }"
                cleaned_sources="${cleaned_sources}${current_source}\n"
            fi

            # Start a new source
            current_source="\"name\": $(echo "$line" | cut -d':' -f2-)"
            in_source=true
        elif [ "$in_source" = true ] && [ -n "$line" ]; then
            # Continue adding fields to the current source
            # Convert YAML format to JSON format
            local field=$(echo "$line" | cut -d':' -f1)
            local value=$(echo "$line" | cut -d':' -f2-)
            current_source="${current_source}, \"$field\": $value"
        fi
    done <<< "$sources_json"

    # Add the last source if there was one
    if [ "$in_source" = true ] && [ -n "$current_source" ]; then
        current_source="{ $current_source }"
        cleaned_sources="${cleaned_sources}${current_source}"
    fi

    # Count actual sources (JSON objects)
    sources_count=$(echo -e "$cleaned_sources" | grep -c "^{")

    if [ "$sources_count" -eq 0 ]; then
        log_warning "No backup sources found for frequency: $backup_type" >&2
        return 1
    else
        log_info "Found $sources_count backup sources for frequency: $backup_type" >&2
        # Return the cleaned sources
        echo -e "$cleaned_sources"
        return 0
    fi
}
# Check if a backup exists for the specified period and path
backup_exists() {
    local backup_type="$1"  # monthly or quarterly
    local year=$(date +%Y)
    local month=$(date +%m)
    local quarter=$(( (10#$month-1)/3+1 ))
    local source_name="$2"  # Optional source name

    local backup_path=""

    case "$backup_type" in
        monthly)
            if [ -n "$source_name" ]; then
                backup_path="${NETWORK_SHARE_PATH}/${BACKUP_ROOT}/monthly/${year}/${month}/${source_name}"
            else
                backup_path="${NETWORK_SHARE_PATH}/${BACKUP_ROOT}/monthly/${year}/${month}"
            fi
            ;;
        quarterly)
            if [ -n "$source_name" ]; then
                backup_path="${NETWORK_SHARE_PATH}/${BACKUP_ROOT}/quarterly/${year}/Q${quarter}/${source_name}"
            else
                backup_path="${NETWORK_SHARE_PATH}/${BACKUP_ROOT}/quarterly/${year}/Q${quarter}"
            fi
            ;;
        *)
            log_error "Unknown backup type: $backup_type"
            return 2
            ;;
    esac

    # Check if directory exists and has content
    if [ -d "$backup_path" ] && [ "$(ls -A "$backup_path" 2>/dev/null)" ]; then
        log_info "$backup_type backup for source '$source_name' already exists at $backup_path"
        return 0
    else
        log_info "No existing $backup_type backup found for source '$source_name'"
        return 1
    fi
}

# Run backup for a specific source
run_source_backup() {
    local backup_type="$1"  # monthly or quarterly
    local source_json="$2"  # JSON representation of the source
    local year=$(date +%Y)
    local month=$(date +%m)
    local quarter=$(( (10#$month-1)/3+1 ))

    # Extract source details using yq
    log_debug "source_json: $source_json"
    local source_name=$(echo "$source_json" | yq eval '.name' -)
    local source_remote=$(echo "$source_json" | yq eval '.remote' -)
    local source_path=$(echo "$source_json" | yq eval '.path' -)

    # Build the full source path
    local full_source_path="${source_remote}${source_path}"

    # Build the destination path
    local destination_path=""
    case "$backup_type" in
        monthly)
            destination_path="${NETWORK_SHARE_PATH}/${BACKUP_ROOT}/${year}/monthly/${month}/${source_name}"
            ;;
        quarterly)
            destination_path="${NETWORK_SHARE_PATH}/${BACKUP_ROOT}/${year}/quarterly/Q${quarter}/${source_name}"
            ;;
        *)
            log_error "Unknown backup type: $backup_type"
            return 1
            ;;
    esac

    # Create destination directory if it doesn't exist
    sudo mkdir -p "$destination_path"

    log_info "Starting $backup_type backup for source '$source_name' from $full_source_path to $destination_path"

    # Build the rclone command
    local rclone_cmd="rclone sync"
    local filter_file=""

    # Check if we have includes or excludes
    local has_includes=$(echo "$source_json" | yq eval '.includes | length > 0' -)
    local has_excludes=$(echo "$source_json" | yq eval '.excludes | length > 0' -)

    if [ "$has_includes" = "true" ] || [ "$has_excludes" = "true" ]; then
        # Create a filter file
        filter_file="${LOG_DIR}/filter-${source_name}-$(date +%Y%m%d%H%M%S).txt"
        touch "$filter_file"

        # Add includes if specified
        if [ "$has_includes" = "true" ]; then
            echo "$source_json" | yq eval '.includes[]' - | while read -r pattern; do
                echo "+ $pattern" >> "$filter_file"
            done
            # Add a final rule to exclude everything else if includes are specified
            echo "- **" >> "$filter_file"
        fi

        # Add excludes if specified
        if [ "$has_excludes" = "true" ]; then
            echo "$source_json" | yq eval '.excludes[]' - | while read -r pattern; do
                echo "- $pattern" >> "$filter_file"
            done
        fi

        # Use the filter file
        rclone_cmd="$rclone_cmd --filter-from=\"$filter_file\""
    fi

    # Complete the command
    log_file="${LOG_DIR}/${backup_type}-${source_name// /_}-$(date +%Y%m%d%H%M%S).log"
    rclone_cmd="sudo $rclone_cmd \"$full_source_path\" \"$destination_path\" --config=\"$RCLONE_CONFIG\" $RCLONE_OPTIONS --log-file=\"$log_file\""
    log_debug "working directory: $(pwd)"
    log_debug "Executing rclone command: $rclone_cmd"

    # Execute the command
    eval $rclone_cmd
    local status=$?

    # Clean up filter file if it exists
    if [ -n "$filter_file" ] && [ -f "$filter_file" ]; then
        rm "$filter_file"
    fi

    if [ $status -eq 0 ]; then
        log_info "$backup_type backup for source '$source_name' completed successfully"
    else
        log_error "$backup_type backup for source '$source_name' failed with error code $status"
    fi

    return $status
}

#Run all backups for specified type
run_backup() {
    local backup_type="$1"  # monthly or quarterly
    local force="$2"  # Whether to force backup even if it exists
    local overall_status=0

    # Notify backup start
    notify_backup_started "$backup_type"

    # Get sources for this backup type
    local sources_json=$(parse_backup_sources "$backup_type")
    local parse_status=$?

    # Debug the raw sources_json to help diagnose issues
    log_debug "Raw BACKUP_SOURCES json before processing:\n$sources_json"

    if [ $parse_status -ne 0 ] || [ -z "$sources_json" ]; then
        log_error "No sources found for $backup_type backup"
        notify_backup_completed "$backup_type" 1
        return 1
    fi

    # Process each source individually
    echo -e "$sources_json" | while read -r source_json; do
        # Skip empty lines
        if [ -z "$source_json" ]; then
            continue
        fi

        log_debug "Processing backup source JSON: $source_json"

        # Extract source name
        local source_name=$(echo "$source_json" | yq eval '.name' -)

        # Skip if empty
        if [ -z "$source_name" ]; then
            continue
        fi

        log_info "Processing backup source: $source_name"

        # Check if backup exists (unless forced)
        if [ "$force" -eq 1 ] || ! backup_exists "$backup_type" "$source_name"; then
            run_source_backup "$backup_type" "$source_json"
            local source_status=$?

            # Update overall status
            [ $source_status -ne 0 ] && overall_status=1
        else
            log_info "Skipping $backup_type backup for source '$source_name' as it already exists (use --force to override)"
        fi
    done

    # Notify completion
    notify_backup_completed "$backup_type" $overall_status

    return $overall_status
}
