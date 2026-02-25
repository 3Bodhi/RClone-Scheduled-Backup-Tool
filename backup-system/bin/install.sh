#!/bin/bash

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHD_DIR="${SCRIPT_DIR}/conf/launchd"
USER_LAUNCHD_DIR="${HOME}/Library/LaunchAgents"

# Check for dependencies
check_dependencies() {
    local missing_deps=0

    # Check for rclone
    if ! command -v rclone &> /dev/null; then
        echo "rclone is required but not installed."
        echo "Install it with: brew install rclone"
        missing_deps=1
    fi

    # Check for yq (YAML parser)
    if ! command -v yq &> /dev/null; then
        echo "yq is required but not installed."
        echo "Install it with: brew install yq"
        missing_deps=1
    fi

    # Optional: Check for terminal-notifier for better notifications
    if ! command -v terminal-notifier &> /dev/null; then
        echo "NOTE: terminal-notifier is not installed. Notifications will use osascript instead."
        echo "To install: brew install terminal-notifier"
    fi

    if [ $missing_deps -eq 1 ]; then
        echo "Please install the missing dependencies and run this script again."
        exit 1
    fi
}

# Install launchd scripts
install_launchd_scripts() {
    echo "Setting up LaunchD scripts..."

    # Ensure directories exist
    mkdir -p "$USER_LAUNCHD_DIR"

    # Process monthly backup plist
    if [ -f "${LAUNCHD_DIR}/com.user.backup.monthly.plist.template" ]; then
        echo "Generating monthly backup LaunchD configuration..."
        # Read the template and replace the path placeholder
        sed "s|/path/to/backup-system|${SCRIPT_DIR}|g" \
            "${LAUNCHD_DIR}/com.user.backup.monthly.plist.template" > \
            "${LAUNCHD_DIR}/com.user.backup.monthly.plist"

        # Copy to user's LaunchAgents directory
        cp "${LAUNCHD_DIR}/com.user.backup.monthly.plist" "$USER_LAUNCHD_DIR/"

        # Load the job
        echo "Loading monthly backup LaunchD job..."
        launchctl unload "${USER_LAUNCHD_DIR}/com.user.backup.monthly.plist" 2>/dev/null || true
        launchctl load "${USER_LAUNCHD_DIR}/com.user.backup.monthly.plist"
    else
        echo "ERROR: Monthly backup template not found at ${LAUNCHD_DIR}/com.user.backup.monthly.plist.template"
    fi

    # Process quarterly backup plist
    if [ -f "${LAUNCHD_DIR}/com.user.backup.quarterly.plist.template" ]; then
        echo "Generating quarterly backup LaunchD configuration..."
        # Read the template and replace the path placeholder
        sed "s|/path/to/backup-system|${SCRIPT_DIR}|g" \
            "${LAUNCHD_DIR}/com.user.backup.quarterly.plist.template" > \
            "${LAUNCHD_DIR}/com.user.backup.quarterly.plist"

        # Copy to user's LaunchAgents directory
        cp "${LAUNCHD_DIR}/com.user.backup.quarterly.plist" "$USER_LAUNCHD_DIR/"

        # Load the job
        echo "Loading quarterly backup LaunchD job..."
        launchctl unload "${USER_LAUNCHD_DIR}/com.user.backup.quarterly.plist" 2>/dev/null || true
        launchctl load "${USER_LAUNCHD_DIR}/com.user.backup.quarterly.plist"
    else
        echo "ERROR: Quarterly backup template not found at ${LAUNCHD_DIR}/com.user.backup.quarterly.plist.template"
    fi

    echo "LaunchD services installed and loaded successfully."
}

# Configure rclone
configure_rclone() {
    # Check if rclone is already configured
    if [ ! -f "${SCRIPT_DIR}/conf/rclone.conf" ]; then
        echo "Configuring rclone..."

        # Either copy an existing config or run rclone config
        if [ -f "${HOME}/.config/rclone/rclone.conf" ]; then
            echo "Found existing rclone config, copying..."
            cp "${HOME}/.config/rclone/rclone.conf" "${SCRIPT_DIR}/conf/rclone.conf"
        else
            echo "No existing rclone config found."
            echo "Please run 'rclone config' to set up your Dropbox remote."
            exit 1
        fi
    else
        echo "rclone already configured."
    fi
}

# Set up initial config
setup_config() {
    if [ ! -f "${SCRIPT_DIR}/conf/backup-config.yml" ]; then
        echo "Creating configuration from template..."
        cp "${SCRIPT_DIR}/conf/backup-config.yml.template" "${SCRIPT_DIR}/conf/backup-config.yml"
        echo "Please edit ${SCRIPT_DIR}/conf/backup-config.yml to configure your backup settings."
        # Optional: open editor automatically
        # ${EDITOR:-vi} "${SCRIPT_DIR}/conf/backup-config.yml"
    else
        echo "Configuration file already exists."
    fi
}


# Main installation process
main() {
    echo "=== Installing Dropbox Backup System ==="

    # Check dependencies
    check_dependencies

    # Create necessary directories
    mkdir -p "${SCRIPT_DIR}/logs"
    mkdir -p "${SCRIPT_DIR}/conf"

    # Set up configuration
    setup_config

    # Configure rclone
    configure_rclone

    # Make scripts executable
    chmod +x "${SCRIPT_DIR}/bin/backup-runner.sh"

    # Install launchd scripts
    install_launchd_scripts

    echo "=== Installation Complete ==="
    echo "Please edit the configuration file at: ${SCRIPT_DIR}/conf/backup-config.yml"
    echo "To run a backup manually: ${SCRIPT_DIR}/bin/backup-runner.sh --type both"
}

# Run the main installation
main
