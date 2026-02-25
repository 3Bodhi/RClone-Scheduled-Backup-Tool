#!/bin/bash

# Determine script directory and source core library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/core.sh"

# Initialize the environment
init_environment

# Parse command line arguments
backup_type=""
force=0

print_usage() {
    echo "Backup Runner v${VERSION}"
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -t, --type TYPE    Backup type (monthly, quarterly, or both)"
    echo "  -f, --force        Force backup even if one exists for current period"
    echo "  -v, --version      Display version information"
    echo "  -h, --help         Display this help message"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--type)
            backup_type="$2"
            shift 2
            ;;
        -f|--force)
            force=1
            shift
            ;;
        -v|--version)
            echo "Backup Runner v${VERSION}"
            exit 0
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate backup type
if [ -z "$backup_type" ]; then
    backup_type="both"
elif [[ ! "$backup_type" =~ ^(monthly|quarterly|both)$ ]]; then
    log_error "Invalid backup type: $backup_type. Must be monthly, quarterly, or both."
    exit 1
fi

# Check and mount network share if needed
if ! is_network_share_mounted; then
    log_info "Network share not mounted, attempting to mount"
    if ! mount_network_share; then
        log_error "Failed to mount network share. Exiting."
        notify_backup_completed "Backup" 1
        exit 1
    fi
fi

# Perform backups based on type
status=0

if [[ "$backup_type" == "monthly" || "$backup_type" == "both" ]]; then
    log_info "Running monthly backups"
    run_backup "monthly" "$force"
    monthly_status=$?
    [ $monthly_status -ne 0 ] && status=1
fi

if [[ "$backup_type" == "quarterly" || "$backup_type" == "both" ]]; then
    log_info "Running quarterly backups"
    run_backup "quarterly" "$force"
    quarterly_status=$?
    [ $quarterly_status -ne 0 ] && status=1
fi

# Exit with appropriate status code
exit $status
