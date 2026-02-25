#!/bin/bash
# Install and load LaunchD jobs for scheduled backups.
# Safe to re-run: existing jobs are unloaded before reloading.
#
# Usage: schedule-launchd.sh [--uninstall]
#   --uninstall   Remove LaunchD jobs without reinstalling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHD_TEMPLATE_DIR="${SCRIPT_DIR}/conf/launchd"
USER_LAUNCHD_DIR="${HOME}/Library/LaunchAgents"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || die "LaunchD scheduling is macOS only."

UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --uninstall) UNINSTALL=1 ;;
        --help|-h)
            echo "Usage: $0 [--uninstall]"
            echo "  --uninstall   Remove LaunchD jobs"
            exit 0
            ;;
        *) die "Unknown option: $arg" ;;
    esac
done

uid=$(id -u)
mkdir -p "$USER_LAUNCHD_DIR"

for job in monthly quarterly; do
    local_plist="${LAUNCHD_TEMPLATE_DIR}/com.user.backup.${job}.plist"
    dest_plist="${USER_LAUNCHD_DIR}/com.user.backup.${job}.plist"

    # Always bootout first (safe no-op if not loaded)
    launchctl bootout "gui/${uid}" "$dest_plist" 2>/dev/null || true

    if [[ "$UNINSTALL" -eq 1 ]]; then
        rm -f "$dest_plist" "$local_plist"
        echo "Removed: com.user.backup.${job}"
        continue
    fi

    template="${LAUNCHD_TEMPLATE_DIR}/com.user.backup.${job}.plist.template"
    [[ -f "$template" ]] || { echo "WARNING: Template not found: $template — skipping."; continue; }

    sed "s|/path/to/backup-system|${SCRIPT_DIR}|g" "$template" > "$local_plist"
    cp "$local_plist" "$dest_plist"

    launchctl bootstrap "gui/${uid}" "$dest_plist" \
        && echo "Loaded: com.user.backup.${job}" \
        || echo "WARNING: Could not load com.user.backup.${job} — try manually: launchctl bootstrap gui/${uid} $dest_plist"
done
