#!/bin/bash

# Send notification using osascript (for macOS)
send_notification_macos() {
    local title="$1"
    local message="$2"

    osascript -e "display notification \"$message\" with title \"$title\""
}

# Send notification using terminal-notifier (more features if installed)
send_notification_terminal_notifier() {
    local title="$1"
    local message="$2"

    if command -v terminal-notifier &> /dev/null; then
        terminal-notifier -title "$title" -message "$message" -group "backup-system"
    else
        send_notification_macos "$title" "$message"
    fi
}

# Cross-platform notification function
send_notification() {
    local title="$1"
    local message="$2"

    log_info "Notification: $title - $message"

    case "$(uname)" in
        Darwin)
            # macOS
            send_notification_terminal_notifier "$title" "$message"
            ;;
        Linux)
            # Linux (using notify-send if available)
            if command -v notify-send &> /dev/null; then
                notify-send "$title" "$message"
            else
                echo "Notification: $title - $message"
            fi
            ;;
        *)
            # Default to echo for unsupported platforms
            echo "Notification: $title - $message"
            ;;
    esac
}

# Backup started notification
notify_backup_started() {
    local backup_type="$1"
    send_notification "Backup Started" "The $backup_type backup has started."
}

# Backup completed notification
notify_backup_completed() {
    local backup_type="$1"
    local status="$2"

    if [ "$status" -eq 0 ]; then
        send_notification "Backup Completed" "The $backup_type backup completed successfully."
    else
        send_notification "Backup Failed" "The $backup_type backup failed with error code $status."
    fi
}
