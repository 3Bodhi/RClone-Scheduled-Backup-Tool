#!/bin/bash
# Notification dispatcher.
# Reads NOTIFY_BACKENDS (space-separated string set by core.sh) and sources
# the matching backend file from lib/notify/{backend}.sh at init time.
#
# To add a new backend: create lib/notify/{name}.sh with a _notify_{name}()
# function, then add the name to the backends list in backup-config.yml.

declare -a NOTIFY_BACKENDS_ARRAY=()

# Source backend files listed in $NOTIFY_BACKENDS.
# Called once from init_environment() after config is loaded.
load_notify_backends() {
    read -ra NOTIFY_BACKENDS_ARRAY <<< "$NOTIFY_BACKENDS"
    for backend in "${NOTIFY_BACKENDS_ARRAY[@]}"; do
        local backend_file="${SCRIPT_DIR}/lib/notify/${backend}.sh"
        if [[ -f "$backend_file" ]]; then
            # shellcheck source=/dev/null
            source "$backend_file"
        else
            log_warning "Notification backend not found: lib/notify/${backend}.sh"
        fi
    done
}

# Send a notification through all configured backends.
# Always logs via log_info regardless of NOTIFY_ENABLED.
send_notification() {
    local title="$1"
    local message="$2"

    log_info "Notification: $title — $message"

    [[ "${NOTIFY_ENABLED:-true}" != "true" ]] && return 0

    for backend in "${NOTIFY_BACKENDS_ARRAY[@]}"; do
        case "$backend" in
            macos) _notify_macos "$title" "$message" ;;
            # email) _notify_email "$title" "$message" ;;  # future: lib/notify/email.sh
            # dbus)  _notify_dbus  "$title" "$message" ;;  # future: lib/notify/dbus.sh
            *) log_warning "Unknown notification backend: $backend" ;;
        esac
    done
}

notify_backup_started() {
    local type="$1"
    send_notification "Backup Started" "The $type backup has started."
}

notify_backup_completed() {
    local type="$1"
    local status="$2"
    if [[ "$status" -eq 0 ]]; then
        send_notification "Backup Completed" "The $type backup completed successfully."
    else
        send_notification "Backup Failed" "The $type backup failed (exit $status)."
    fi
}
