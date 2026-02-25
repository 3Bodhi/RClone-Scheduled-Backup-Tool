#!/bin/bash
# Core initialization: sets constants, loads config, sources all library modules.
# SCRIPT_DIR must be set by the caller (backup-runner.sh) before sourcing this file.

# Source library modules — order matters: logger first, then backup, then notify.
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/backup.sh"
source "${SCRIPT_DIR}/lib/notify/notify.sh"

CONFIG_FILE="${SCRIPT_DIR}/conf/backup-config.yml"
VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "0.1.0")

# Load configuration from backup-config.yml into named global variables.
# Uses yq to emit the full config as JSON, then extracts each field with jq.
# No eval. Exits 1 on missing dependencies, missing config, or missing required fields.
load_config() {
    if ! command -v yq &>/dev/null; then
        echo "yq is required but not installed. Install with: brew install yq"; exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "jq is required but not installed. Install with: brew install jq"; exit 1
    fi
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Config file not found: $CONFIG_FILE"; exit 1
    fi

    local cfg
    cfg=$(yq -o json . "$CONFIG_FILE") || { echo "Failed to parse $CONFIG_FILE"; exit 1; }

    DEST_REMOTE=$(jq -r   '.destination.remote'              <<< "$cfg")
    DEST_PATH=$(jq -r     '.destination.path'                <<< "$cfg")
    BACKUP_ROOT=$(jq -r   '.backup_root'                     <<< "$cfg")
    RCLONE_CONFIG=$(jq -r '.rclone_config'                   <<< "$cfg")
    RCLONE_OPTIONS=$(jq -r '.rclone_options // ""'           <<< "$cfg")
    LOG_DIR=$(jq -r       '.log_dir // "logs"'               <<< "$cfg")
    DEBUG=$(jq -r         '.debug // "false"'                <<< "$cfg")
    NOTIFY_ENABLED=$(jq -r '.notifications.enabled // "true"' <<< "$cfg")
    NOTIFY_BACKENDS=$(jq -r '.notifications.backends[]? // empty' <<< "$cfg" | tr '\n' ' ')

    # Resolve relative paths against SCRIPT_DIR
    [[ "$RCLONE_CONFIG" != /* ]] && RCLONE_CONFIG="${SCRIPT_DIR}/${RCLONE_CONFIG}"
    [[ "$LOG_DIR"       != /* ]] && LOG_DIR="${SCRIPT_DIR}/${LOG_DIR}"

    # Validate required fields
    for var in DEST_REMOTE DEST_PATH BACKUP_ROOT RCLONE_CONFIG; do
        if [[ -z "${!var}" || "${!var}" == "null" ]]; then
            echo "Required config field missing or null: $var"; exit 1
        fi
    done

    export DEST_REMOTE DEST_PATH BACKUP_ROOT RCLONE_CONFIG RCLONE_OPTIONS
    export LOG_DIR DEBUG NOTIFY_ENABLED NOTIFY_BACKENDS
}

# Set up the environment: create log directory, load config, init logging, load backends.
init_environment() {
    # Bootstrap a minimal LOG_DIR so mkdir succeeds even before config is read.
    LOG_DIR="${SCRIPT_DIR}/logs"
    mkdir -p "$LOG_DIR"

    load_config

    mkdir -p "$LOG_DIR"
    init_logging
    load_notify_backends
}
