#!/bin/bash

# Source other library modules
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/network.sh"
source "${SCRIPT_DIR}/lib/notifications.sh"
source "${SCRIPT_DIR}/lib/backup.sh"

# Script constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/conf"
CONFIG_FILE="${CONFIG_DIR}/backup-config.yml"
LOG_DIR="${SCRIPT_DIR}/logs"
VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "0.1.0")

# Load configuration from YAML
# This uses yq, a YAML parser for bash (needs to be installed)
load_config() {
    if ! command -v yq &> /dev/null; then
        echo "yq is required but not installed. Please install it first."
        exit 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    # Export simple key-value pairs as environment variables, excluding arrays/objects
    eval $(yq eval 'with_entries(select(.key != "BACKUP_SOURCES" and .value | type != "object")) | to_entries | .[] | "export " + .key + "=\"" + .value + "\""' "$CONFIG_FILE")
    log_debug "Setting Environment Variables:\n$(yq eval 'with_entries(select(.key != "BACKUP_SOURCES" and .value | type != "object" and type != "sequence")) | to_entries | .[] | "export " + .key + "=\"" + .value + "\""' "$CONFIG_FILE")"
    # BACKUP_SOURCES are handled separately backup.sh's parse_backup_sources() function.

    # Check if required variables are set
    for var in NETWORK_SHARE_URL NETWORK_SHARE_PATH BACKUP_ROOT RCLONE_CONFIG; do
        if [ -z "${!var}" ]; then
            echo "Required configuration variable $var is not set in $CONFIG_FILE"
            exit 1
        fi
    done
}

# Initialize the environment
init_environment() {
    # Create log directory if it doesn't exist
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
    fi

    # Load configuration
    load_config

    # Initialize logging
    init_logging
}
