#!/bin/bash

# Initialize logging
init_logging() {
    LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m%d).log"
    export LOG_FILE
}

# Log message with level
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Log informational message
log_info() {
    log_message "INFO" "$1"
}

# Log warning message
log_warning() {
    log_message "WARNING" "$1"
}

# Log error message
log_error() {
    log_message "ERROR" "$1"
}

# Log debug message (only if debug is enabled)
log_debug() {
    if [ "${DEBUG:-0}" -eq 1 ]; then
        log_message "DEBUG" "$1"
    fi
}
