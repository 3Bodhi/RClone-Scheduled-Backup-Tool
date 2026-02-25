#!/bin/bash
# Backup runner — entry point for manual and scheduled backup runs.
# Usage: backup-runner.sh [--type monthly|quarterly|both] [--force]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/core.sh"

print_usage() {
    echo "Backup Runner v${VERSION}"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -t, --type TYPE    Backup type: monthly, quarterly, or both (default: both)"
    echo "  -f, --force        Force backup even if one already exists for the current period"
    echo "  -v, --version      Display version information"
    echo "  -h, --help         Display this help message"
}

# Parse arguments before init_environment so --help/--version work without a config file.
backup_type=""
force=0

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
            VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "0.1.0")
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

# Default type
[[ -z "$backup_type" ]] && backup_type="both"

if [[ ! "$backup_type" =~ ^(monthly|quarterly|both)$ ]]; then
    echo "Invalid backup type: $backup_type. Must be monthly, quarterly, or both."
    exit 1
fi

# Initialize environment: loads config, sets up logging, loads notification backends.
init_environment

log_info "=== Backup run started (type: $backup_type, force: $force) ==="

status=0

if [[ "$backup_type" == "monthly" || "$backup_type" == "both" ]]; then
    run_backup "monthly" "$force" || status=1
fi

if [[ "$backup_type" == "quarterly" || "$backup_type" == "both" ]]; then
    run_backup "quarterly" "$force" || status=1
fi

log_info "=== Backup run finished (exit: $status) ==="
exit $status
