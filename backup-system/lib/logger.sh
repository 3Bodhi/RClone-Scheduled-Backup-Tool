#!/bin/bash

# Initialize the run log file.
# LOG_DIR must already be set and exist before calling this.
init_logging() {
    LOG_FILE="${LOG_DIR}/$(date +%Y%m%d)-runner.log"
    export LOG_FILE
}

_log_write() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info()    { _log_write "INFO"    "$1"; }
log_warning() { _log_write "WARNING" "$1"; }
log_error()   { _log_write "ERROR"   "$1"; }

log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && _log_write "DEBUG" "$1"
}
