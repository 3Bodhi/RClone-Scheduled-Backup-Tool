#!/bin/bash
# One-time installation and setup script.
# Sets up config, configures the rclone SMB remote, installs LaunchD jobs.
# Safe to re-run: existing config and remotes are preserved.
#
# Usage: install.sh [--no-launchd]
#   --no-launchd   Skip LaunchD job installation (useful for manual/server setups)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_DIR="${SCRIPT_DIR}/conf"
LAUNCHD_TEMPLATE_DIR="${CONF_DIR}/launchd"
USER_LAUNCHD_DIR="${HOME}/Library/LaunchAgents"
RCLONE_CONF="${CONF_DIR}/rclone.conf"
BACKUP_CONF="${CONF_DIR}/backup-config.yml"
SKIP_LAUNCHD=0

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --no-launchd) SKIP_LAUNCHD=1 ;;
        --help|-h)
            echo "Usage: $0 [--no-launchd]"
            echo "  --no-launchd   Skip LaunchD job installation"
            exit 0
            ;;
        *) die "Unknown option: $arg" ;;
    esac
done

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
check_dependencies() {
    local missing=0

    command -v rclone &>/dev/null || { echo "  [missing] rclone  — install: brew install rclone"; missing=1; }
    command -v yq     &>/dev/null || { echo "  [missing] yq      — install: brew install yq";     missing=1; }
    command -v jq     &>/dev/null || { echo "  [missing] jq      — install: brew install jq";     missing=1; }

    # Warn (don't fail) if terminal-notifier is absent
    command -v terminal-notifier &>/dev/null \
        || echo "  [optional] terminal-notifier not found — notifications will use osascript"

    # Verify mikefarah yq (not the Python wrapper)
    if command -v yq &>/dev/null; then
        yq --version 2>&1 | grep -q "version v[4-9]" \
            || { echo "  [wrong yq] mikefarah yq v4+ required — install: brew install yq"; missing=1; }
    fi

    [[ $missing -eq 1 ]] && die "Install missing dependencies and re-run."
}

# ---------------------------------------------------------------------------
# Config file setup
# ---------------------------------------------------------------------------
setup_config() {
    if [[ ! -f "$BACKUP_CONF" ]]; then
        say "Creating backup-config.yml from template..."
        cp "${CONF_DIR}/backup-config.yml.template" "$BACKUP_CONF"
        chmod 600 "$BACKUP_CONF"
        echo ""
        echo "  Edit your configuration before proceeding:"
        echo "    $BACKUP_CONF"
        echo ""
        echo "  Then re-run install.sh."
        exit 0
    else
        say "backup-config.yml already exists — skipping template copy."
        chmod 600 "$BACKUP_CONF"
    fi
}

# ---------------------------------------------------------------------------
# rclone SMB remote setup
# Reads destination.remote from the backup config and adds the remote to
# rclone.conf if it is not already present.
# ---------------------------------------------------------------------------
setup_smb_remote() {
    local remote_name
    remote_name=$(yq -r '.destination.remote' "$BACKUP_CONF" 2>/dev/null) \
        || die "Could not read destination.remote from $BACKUP_CONF"

    [[ -z "$remote_name" || "$remote_name" == "null" ]] \
        && die "destination.remote is not set in $BACKUP_CONF"

    # Check if the remote already exists in rclone.conf
    if [[ -f "$RCLONE_CONF" ]] && grep -q "^\[$remote_name\]" "$RCLONE_CONF" 2>/dev/null; then
        say "rclone remote '$remote_name' already configured in rclone.conf — skipping."
        return 0
    fi

    say "Setting up rclone SMB remote: '$remote_name'"
    echo ""
    echo "  Enter the SMB server details for remote '$remote_name'."
    echo "  (The password will be stored in rclone.conf using rclone obscure.)"
    echo ""

    read -rp "  SMB host (e.g. server.example.com):      " smb_host
    read -rp "  SMB share path (e.g. sharename/subdir):  " smb_share
    read -rp "  Username:                                 " smb_user
    read -rsp "  Password:                                " smb_pass
    echo ""

    [[ -z "$smb_host" || -z "$smb_user" || -z "$smb_pass" ]] \
        && die "Host, username, and password are required."

    local obscured_pass
    obscured_pass=$(rclone obscure "$smb_pass") \
        || die "rclone obscure failed — check your rclone installation."

    # Append the SMB remote stanza to rclone.conf (create file if needed)
    mkdir -p "$CONF_DIR"
    {
        echo ""
        echo "[$remote_name]"
        echo "type = smb"
        echo "host = $smb_host"
        echo "user = $smb_user"
        echo "pass = $obscured_pass"
    } >> "$RCLONE_CONF"

    chmod 600 "$RCLONE_CONF"
    say "Remote '$remote_name' added to rclone.conf."

    # Also update destination.path in backup-config.yml if it still has the placeholder
    local current_path
    current_path=$(yq -r '.destination.path' "$BACKUP_CONF")
    if [[ "$current_path" == "sharename/path/to/backup/root" ]]; then
        say "Updating destination.path in backup-config.yml to: $smb_share"
        yq -i ".destination.path = \"$smb_share\"" "$BACKUP_CONF"
    fi
}

# ---------------------------------------------------------------------------
# Connectivity test
# ---------------------------------------------------------------------------
test_connectivity() {
    local remote_name
    remote_name=$(yq -r '.destination.remote' "$BACKUP_CONF")
    say "Testing connectivity to '$remote_name'..."
    if rclone lsd "${remote_name}:" --config="$RCLONE_CONF" &>/dev/null; then
        say "Connection successful."
    else
        echo "  WARNING: Could not connect to '$remote_name}'."
        echo "  Check your SMB host, credentials, and network, then verify with:"
        echo "    rclone lsd ${remote_name}: --config=${RCLONE_CONF}"
    fi
}

# ---------------------------------------------------------------------------
# LaunchD job installation
# ---------------------------------------------------------------------------
install_launchd() {
    say "Installing LaunchD jobs..."
    mkdir -p "$USER_LAUNCHD_DIR"

    local uid
    uid=$(id -u)

    for job in monthly quarterly; do
        local template="${LAUNCHD_TEMPLATE_DIR}/com.user.backup.${job}.plist.template"
        local generated="${LAUNCHD_TEMPLATE_DIR}/com.user.backup.${job}.plist"
        local dest="${USER_LAUNCHD_DIR}/com.user.backup.${job}.plist"

        if [[ ! -f "$template" ]]; then
            echo "  WARNING: Template not found: $template — skipping $job job."
            continue
        fi

        sed "s|/path/to/backup-system|${SCRIPT_DIR}|g" "$template" > "$generated"
        cp "$generated" "$dest"

        # Use launchctl bootstrap (macOS 10.15+ API; falls back gracefully on older)
        launchctl bootout  "gui/${uid}" "$dest" 2>/dev/null || true
        launchctl bootstrap "gui/${uid}" "$dest" \
            && echo "  Loaded: com.user.backup.${job}" \
            || echo "  WARNING: Could not load com.user.backup.${job} — try: launchctl bootstrap gui/${uid} $dest"
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo "========================================"
    echo "  Backup System Installation"
    echo "========================================"
    echo ""

    check_dependencies

    mkdir -p "${SCRIPT_DIR}/logs" "$CONF_DIR"

    setup_config       # exits early if config was just created from template

    setup_smb_remote

    test_connectivity

    chmod +x "${SCRIPT_DIR}/bin/backup-runner.sh"

    if [[ "$SKIP_LAUNCHD" -eq 1 ]]; then
        say "Skipping LaunchD installation (--no-launchd)."
    else
        install_launchd
    fi

    echo ""
    echo "========================================"
    echo "  Installation complete."
    echo ""
    echo "  Manual run:"
    echo "    ${SCRIPT_DIR}/bin/backup-runner.sh --type both"
    echo ""
    echo "  Logs:"
    echo "    ${SCRIPT_DIR}/logs/"
    echo "========================================"
}

main
