# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A macOS backup system that syncs Dropbox content to a network share on a schedule using rclone. Configured via YAML, scheduled via LaunchD, and implemented entirely in Bash.

## Running & Installation

```bash
# Install (checks dependencies, configures rclone, sets up LaunchD jobs)
./backup-system/bin/install.sh

# Run a backup manually
./backup-system/bin/backup-runner.sh --type monthly
./backup-system/bin/backup-runner.sh --type quarterly
./backup-system/bin/backup-runner.sh --type both
./backup-system/bin/backup-runner.sh --type monthly --force   # bypass existing-backup check
```

No build step, package manager, or test runner — this is a pure shell project.

## Architecture

All code lives under `backup-system/`. The two entry points are `bin/backup-runner.sh` (runs backups) and `bin/install.sh` (one-time setup).

**Library load order** (defined in `lib/core.sh`, which sources everything else):
`logger.sh` → `network.sh` → `notifications.sh` → `backup.sh`

**Execution flow for a backup run:**
1. `backup-runner.sh` calls `init_environment()` (core.sh) — loads config via `yq`, sets up log file
2. Mounts the network share via `mount_network_share()` (network.sh)
3. Calls `run_backup()` (backup.sh), which:
   - Calls `parse_backup_sources()` to extract sources matching the requested frequency from the YAML config
   - For each source, calls `run_source_backup()` which builds an rclone filter file from `includes`/`excludes` and runs `rclone sync`
   - `backup_exists()` checks for an existing timestamped directory and skips unless `--force`
4. Unmounts the share, sends a notification (notifications.sh)

**Backup directory layout on the network share:**
```
{backup_root}/monthly/{year}/{month}/{source_name}/
{backup_root}/quarterly/{year}/Q{n}/{source_name}/
```

**Configuration** (`conf/backup-config.yml`, gitignored — copy from `.template`):
- `network_share.*` — SMB/AFP/NFS URL, mount path, credentials
- `rclone.*` — path to `rclone.conf`, extra flags
- `backup_root` — base path on the network share
- `backup_sources[]` — array of sources, each with `name`, `remote`, `path`, `frequency` (monthly/quarterly/both), and optional `includes`/`excludes` filter lists

**Scheduling:** LaunchD plist templates in `conf/launchd/` are rendered and loaded into `~/Library/LaunchAgents/` by `install.sh`. Monthly runs on the 1st at 2 AM; quarterly runs on the 1st of Jan/Apr/Jul/Oct at 3 AM.

**Dependencies:** `rclone`, `yq` (YAML parsing), `osascript` (built-in macOS), optionally `terminal-notifier` for richer notifications.

## Key Conventions

- `log_info`, `log_warning`, `log_error`, `log_debug` (logger.sh) are the only logging functions — never use raw `echo` for operational output.
- Network share credentials live only in `conf/backup-config.yml` and `conf/rclone.conf`, both gitignored. Never commit these.
- `parse_backup_sources()` uses `yq` with numeric indexing to iterate YAML arrays — maintain this pattern when modifying config parsing.
- The `--force` flag bypasses `backup_exists()` and is the only way to re-run a backup for the current period.
