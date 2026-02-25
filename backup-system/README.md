# Dropbox to Network Share Backup System

A modular, maintainable backup system that performs monthly and quarterly backups from Dropbox to a network share.

## Features

- Scheduled backups (monthly and quarterly)
- Network share mounting
- Notifications for backup start and completion
- Modular design for easy maintenance and extension
- Cross-platform compatibility (primarily macOS)

### Initial Setup

1. Run the installation script: `./bin/install.sh`
2. The script will create configuration files from templates
3. Edit the generated files to add your specific settings

## Configuration

Edit the configuration file at `conf/backup-config.yml` to set up your:
- Network share details
- Backup paths
- rclone options

## Usage

To run a backup manually:

```bash
./bin/backup-runner.sh --type monthly
./bin/backup-runner.sh --type quarterly
./bin/backup-runner.sh --type both
```

Add the `--force` flag to run backups even if they already exist for the current period.
