# rclone Scheduled Backup

Orchestrates scheduled backups from rclone remotes (e.g. Dropbox) to a network share or any other rclone destination. Sources, filters, and cadences are defined in a single YAML file. macOS notifications are sent on start and completion.

## How it works

`backup-runner.sh` reads `conf/backup-config.yml`, finds all sources matching the requested frequency, and runs `rclone sync` for each one. Credentials and remote definitions live entirely in `rclone.conf` — this tool never touches them. Per-source logs are written to `logs/{source-name}/`.

## Requirements

- [rclone](https://rclone.org) — `brew install rclone`
- [yq](https://github.com/mikefarah/yq) (mikefarah, v4+) — `brew install yq`
- [jq](https://jqlang.org) — `brew install jq`
- [terminal-notifier](https://github.com/julienXX/terminal-notifier) *(optional, for richer macOS notifications)* — `brew install terminal-notifier`

## Setup

### 1. Configure your rclone remotes

You need two remotes: one for the **source** (e.g. Dropbox) and one for the **destination** (e.g. an SMB share). Use rclone's interactive config to set them up:

```bash
rclone config
```

See the rclone docs for your specific backend types:
- [Dropbox remote](https://rclone.org/dropbox/)
- [SMB remote](https://rclone.org/smb/)
- [All backends](https://rclone.org/overview/)

Verify your remotes are working before proceeding:

```bash
rclone lsd dropbox:
rclone lsd your-smb-remote:sharename/path
```

### 2. Create your backup config

```bash
cp conf/backup-config.yml.template conf/backup-config.yml
chmod 600 conf/backup-config.yml
```

Edit `conf/backup-config.yml` to set your destination remote, backup sources, and rclone options. The template has inline documentation for every field.

### 3. Point to your rclone.conf

By default the config expects `conf/rclone.conf`. You can either copy your existing config there or point `rclone_config` at the default location:

```yaml
rclone_config: "/Users/yourname/.config/rclone/rclone.conf"
```

If you copy it, set permissions:
```bash
cp ~/.config/rclone/rclone.conf conf/rclone.conf
chmod 600 conf/rclone.conf
```

## Running backups

```bash
# Run all sources for the current period
./bin/backup-runner.sh

# Run a specific frequency
./bin/backup-runner.sh --type monthly
./bin/backup-runner.sh --type quarterly

# Force a re-run even if a backup already exists for the current period
# (rclone sync is idempotent — only changed files are transferred, no duplicates)
./bin/backup-runner.sh --type monthly --force
```

## Scheduling (macOS LaunchD)

To install scheduled LaunchD jobs (monthly on the 1st at 2 AM, quarterly on the 1st of Jan/Apr/Jul/Oct at 3 AM):

```bash
./bin/schedule-launchd.sh
```

To remove the scheduled jobs:

```bash
./bin/schedule-launchd.sh --uninstall
```

## Configuration reference

```yaml
destination:
  remote: "my-smb"              # rclone remote name (defined in rclone.conf)
  path: "sharename/backups"     # path within the share, no leading slash

backup_root: "dropbox-backups"  # subfolder under destination.path
rclone_config: "conf/rclone.conf"
rclone_options: "--transfers 4 --checkers 8 --stats 60s --retries 3"

log_dir: "logs"

notifications:
  enabled: true
  backends: ["macos"]           # see lib/notify/ for available backends

debug: false                    # true: enable debug logging, keep filter files

backup_sources:
  - name: "My Source"           # used as the log subdirectory name
    remote: "dropbox:"          # source rclone remote
    path: "/Folder/In/Dropbox"
    includes:                   # if non-empty, only these paths are synced
      - "/Active/**"
    excludes: []                # patterns to exclude
    frequency: "monthly"        # monthly | quarterly | both
```

## Logs

```
logs/
  YYYYMMDD-runner.log           # orchestrator log for each run
  {source-name}/
    YYYYMMDD-{type}.log         # rclone output per source per run
  monthly-launchd.log           # LaunchD stdout/stderr (scheduled runs only)
  quarterly-launchd.log
```

## Adding a notification backend

Create `lib/notify/{name}.sh` with a `_notify_{name}()` function, then add the name to `backends:` in your config. The dispatcher in `lib/notify/notify.sh` picks it up automatically.
