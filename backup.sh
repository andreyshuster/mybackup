#!/bin/bash

set -e

# Cleanup function for graceful exit
cleanup() {
    echo ""
    echo "Backup interrupted by user. Cleaning up..."

    # Remove incomplete daily backup if it exists
    if [ -n "$DAILY_BACKUP" ] && [ -d "$DAILY_BACKUP" ]; then
        echo "Removing incomplete backup: $DAILY_BACKUP"
        rm -rf "$DAILY_BACKUP"
    fi


    # Write failure status to destination root folder if DEST is set
    if [ -n "$DEST" ] && [ -d "$DEST" ]; then
        STATUS_FILE="$DEST/last_backup_status.txt"
        {
            echo "BACKUP STATUS: FAILED"
            echo "DATETIME: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "SOURCE: ${SOURCE:-Unknown}"
            echo "DESTINATION: $DEST"
            echo "ERROR: Backup was interrupted or failed"
        } > "$STATUS_FILE"
        echo "Failure status written to: $STATUS_FILE"
    fi

    echo "Cleanup completed. Backup was not finished."
    exit 1
}

# Error handler function
error_handler() {
    local exit_code=$?
    local line_number=$1

    echo ""
    echo "Error: Backup failed at line $line_number with exit code $exit_code"

    # Write failure status to destination root folder if DEST is set
    if [ -n "$DEST" ] && [ -d "$DEST" ]; then
        STATUS_FILE="$DEST/last_backup_status.txt"
        {
            echo "BACKUP STATUS: FAILED"
            echo "DATETIME: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "SOURCE: ${SOURCE:-Unknown}"
            echo "DESTINATION: $DEST"
            echo "ERROR: Backup failed at line $line_number with exit code $exit_code"
            echo "ERROR_LINE: $line_number"
            echo "EXIT_CODE: $exit_code"
            if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
                echo "LOG_FILE: $LOG_FILE"
            fi
        } > "$STATUS_FILE"
        echo "Error status written to: $STATUS_FILE"
    fi

    exit $exit_code
}

# Set up signal and error handlers
trap cleanup SIGINT SIGTERM
trap 'error_handler $LINENO' ERR

usage() {
    echo "Usage: $0 <source_directory> <destination_directory> [encryption_key] [exclude_file]"
    echo "Example: $0 /home/user/documents /backup/location"
    echo "Example with encryption: $0 /home/user/documents /backup/location mykey@example.com"
    echo "Example with exclusions: $0 /home/user/documents /backup/location \"\" excludes.txt"
    echo "Example with both: $0 /home/user/documents /backup/location mykey@example.com excludes.txt"
    echo ""
    echo "Exclude file format (one pattern per line):"
    echo "  .git/"
    echo "  node_modules/"
    echo "  *.tmp"
    echo "  cache/*"
    echo ""
    echo "Note: For encryption, the GPG key must already exist in your keyring"
    echo "      Use empty string \"\" for encryption_key if you want exclusions without encryption"
    exit 1
}

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    usage
fi

SOURCE="$1"
DEST="$2"
ENCRYPTION_KEY="$3"
EXCLUDE_FILE="$4"

if [ -n "$ENCRYPTION_KEY" ] && [ "$ENCRYPTION_KEY" != "" ]; then
    echo "Encryption enabled with key: $ENCRYPTION_KEY"
    if ! gpg --list-keys "$ENCRYPTION_KEY" >/dev/null 2>&1; then
        echo "Error: GPG key '$ENCRYPTION_KEY' not found in keyring"
        echo "Please import the key first with: gpg --import keyfile"
        exit 1
    fi
fi

EXCLUDE_OPTS=""
if [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
    echo "Using exclusion file: $EXCLUDE_FILE"
    EXCLUDE_OPTS="--exclude-from=$EXCLUDE_FILE"
elif [ -n "$EXCLUDE_FILE" ]; then
    echo "Warning: Exclude file '$EXCLUDE_FILE' not found - proceeding without exclusions"
fi

if [ ! -d "$SOURCE" ]; then
    echo "Error: Source directory '$SOURCE' does not exist"
    exit 1
fi

if [ ! -d "$DEST" ]; then
    echo "Creating destination directory: $DEST"
    mkdir -p "$DEST"
fi

DATE=$(date +%Y-%m-%d)
WEEK=$(date +%Y-W%U)

CURRENT_DIR="$DEST/current"
DAILY_DIR="$DEST/daily"
WEEKLY_DIR="$DEST/weekly"

mkdir -p "$DAILY_DIR" "$WEEKLY_DIR"

echo "Starting incremental backup of '$SOURCE' to '$DEST'"

if [ -d "$CURRENT_DIR" ]; then
    echo "Previous backup found - creating full backup..."
else
    echo "No previous backup found - creating full backup..."
fi

DAILY_BACKUP="$DAILY_DIR/backup_$DATE"
mkdir -p "$DAILY_BACKUP"

echo "Syncing files with rsync..."

# Create log file for this backup
LOG_FILE="$DEST/rsync_log_$DATE.txt"
echo "Rsync output will be logged to: $LOG_FILE"

# Run rsync and capture output
rsync -rvL --times --delete --itemize-changes $EXCLUDE_OPTS "$SOURCE/" "$DAILY_BACKUP/" 2>&1 | tee "$LOG_FILE"

# Capture rsync exit code
RSYNC_EXIT_CODE=${PIPESTATUS[0]}

# If rsync failed, show detailed error information
if [ $RSYNC_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "ERROR: rsync failed with exit code $RSYNC_EXIT_CODE"
    echo ""
    echo "Common rsync exit codes:"
    echo "  23 = Partial transfer due to error (some files failed)"
    echo "  24 = Partial transfer due to vanished source files"
    echo ""
    echo "Failed files/errors logged to: $LOG_FILE"
    echo ""
    echo "To see errors, run: grep -E 'rsync:|error|failed|Permission denied' $LOG_FILE"
    echo ""

    # Extract and show specific errors if any
    if grep -qE 'rsync:|error|failed|Permission denied|cannot|denied' "$LOG_FILE"; then
        echo "Detected errors in rsync output:"
        grep -E 'rsync:|error|failed|Permission denied|cannot|denied' "$LOG_FILE" | head -20
    fi

    exit $RSYNC_EXIT_CODE
fi

if [ -d "$CURRENT_DIR" ]; then
    rm -rf "$CURRENT_DIR"
fi

echo "Daily backup created: $DAILY_BACKUP"

if [ $(date +%u) -eq 7 ]; then
    echo "Sunday detected - creating weekly backup"
    WEEKLY_BACKUP="$WEEKLY_DIR/weekly_$WEEK"
    cp -r "$DAILY_BACKUP" "$WEEKLY_BACKUP"

    echo "Compressing weekly backup..."
    tar -czf "$WEEKLY_BACKUP.tar.gz" -C "$WEEKLY_DIR" "$(basename "$WEEKLY_BACKUP")"
    rm -rf "$WEEKLY_BACKUP"

    if [ -n "$ENCRYPTION_KEY" ]; then
        echo "Encrypting weekly backup..."
        gpg --trust-model always --encrypt --recipient "$ENCRYPTION_KEY" --output "$WEEKLY_BACKUP.tar.gz.gpg" "$WEEKLY_BACKUP.tar.gz"
        rm -f "$WEEKLY_BACKUP.tar.gz"
        echo "Weekly backup created and encrypted: $WEEKLY_BACKUP.tar.gz.gpg"
    else
        echo "Weekly backup created: $WEEKLY_BACKUP.tar.gz"
    fi
fi

echo "Cleaning up old backups..."

find "$DAILY_DIR" -maxdepth 1 -type d -name "backup_*" -mtime +6 -exec rm -rf {} \;
echo "Removed daily backups older than 7 days"

if [ -n "$ENCRYPTION_KEY" ]; then
    find "$WEEKLY_DIR" -name "weekly_*.tar.gz.gpg" -mtime +83 -delete
else
    find "$WEEKLY_DIR" -name "weekly_*.tar.gz" -mtime +83 -delete
fi
echo "Removed weekly backups older than 12 weeks"

BACKUP_SIZE=$(du -sh "$DAILY_BACKUP" | cut -f1)
echo "Backup completed successfully!"
echo "Backup size: $BACKUP_SIZE"
echo "Daily backup location: $DAILY_BACKUP"

# Write status to destination root folder
STATUS_FILE="$DEST/last_backup_status.txt"
{
    echo "BACKUP STATUS: SUCCESS"
    echo "DATETIME: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "SOURCE: $SOURCE"
    echo "DESTINATION: $DEST"
    echo "BACKUP_SIZE: $BACKUP_SIZE"
    echo "DAILY_BACKUP: $DAILY_BACKUP"
    if [ -n "$ENCRYPTION_KEY" ]; then
        echo "ENCRYPTION: Enabled ($ENCRYPTION_KEY)"
    else
        echo "ENCRYPTION: Disabled"
    fi
} > "$STATUS_FILE"
echo "Status written to: $STATUS_FILE"
