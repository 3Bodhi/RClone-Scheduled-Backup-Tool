#!/bin/bash
# macOS notification backend.
# Provides _notify_macos(), called by the dispatcher in notify.sh.
# Uses terminal-notifier if available; falls back to osascript.

_notify_macos() {
    local title="$1"
    local message="$2"

    if command -v terminal-notifier &>/dev/null; then
        terminal-notifier -title "$title" -message "$message" -group "backup-system"
    else
        osascript -e "display notification \"$message\" with title \"$title\""
    fi
}
