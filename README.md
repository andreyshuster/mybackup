# MyBackup

A robust incremental backup solution with local and remote backup capabilities, featuring GPG encryption and intelligent retention policies.

## Features

- **Incremental backups** using rsync with hard links to save space
- **Local and remote backup** support (SSH-based remote backups)
- **GPG encryption** for secure weekly backups
- **Intelligent retention**: 7 days of daily backups, 12 weeks of weekly backups
- **Exclude patterns** support to skip unwanted files/directories
- **Signal handling** for graceful interruption and cleanup
- **Automatic weekly compression** every Sunday

## Files

- `backup.sh` - Main backup script with full feature set (local backups)
- `backup-remote.sh` - Simplified script for remote backups via SSH
- `excludes.txt` - Common exclude patterns for development environments

## Usage

### Local Backups

```bash
./backup.sh <source_directory> <destination_directory> [encryption_key] [exclude_file]
```

**Examples:**
```bash
# Basic backup
./backup.sh /home/user/documents /backup/location

# With GPG encryption
./backup.sh /home/user/documents /backup/location mykey@example.com

# With exclusions (no encryption)
./backup.sh /home/user/documents /backup/location "" excludes.txt

# With both encryption and exclusions
./backup.sh /home/user/documents /backup/location mykey@example.com excludes.txt
```

### Remote Backups

```bash
./backup-remote.sh <source_directory> <remote_destination>
```

**Examples:**
```bash
# Remote backup via SSH
./backup-remote.sh /home/user/documents user@server:/backup/location

# Local backup (fallback)
./backup-remote.sh /home/user/documents /local/backup
```

## Directory Structure

The backup creates the following structure:

```
destination/
├── current/          # Symlink to latest daily backup
├── daily/           # Daily incremental backups
│   ├── backup_2023-12-01/
│   ├── backup_2023-12-02/
│   └── ...
└── weekly/          # Weekly compressed/encrypted backups
    ├── weekly_2023-W48.tar.gz
    ├── weekly_2023-W49.tar.gz.gpg  # If encrypted
    └── ...
```

## Encryption Setup

For GPG encryption support:

1. Generate or import a GPG key:
   ```bash
   gpg --gen-key
   # or
   gpg --import keyfile
   ```

2. Use the key identifier (email or key ID) as the encryption parameter

## Exclude Patterns

The `excludes.txt` file contains common patterns to exclude:
- Version control directories (.git, .svn)
- Dependencies (node_modules, __pycache__)
- Build outputs (dist, build, target)
- IDE files (.vscode, .idea)
- Temporary files (*.tmp, cache/)
- Large media files (*.iso, *.mp4)

Create custom exclude files following the same format (one pattern per line).

## Retention Policy

- **Daily backups**: Kept for 7 days
- **Weekly backups**: Created every Sunday, kept for 12 weeks (3 months)
- **Space efficiency**: Incremental backups use hard links to minimize storage

## Requirements

- `bash`
- `rsync`
- `tar`
- `gpg` (for encryption features)
- `ssh` (for remote backups)
- `find`, `date`, `du` (standard Unix utilities)

## Safety Features

- Graceful signal handling (Ctrl+C cleanup)
- Validation of source directories and GPG keys
- Automatic cleanup of incomplete backups on interruption
- Broken symlink detection and removal