#!/bin/bash

set -e

usage() {
    echo "Usage: $0 <source_directory> <remote_destination>"
    echo "Example: $0 /home/user/documents user@server:/backup/location"
    echo "Example: $0 /home/user/documents /local/backup"
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

SOURCE="$1"
DEST="$2"

if [ ! -d "$SOURCE" ]; then
    echo "Error: Source directory '$SOURCE' does not exist"
    exit 1
fi

DATE=$(date +%Y-%m-%d)

# Check if destination is remote (contains :)
if [[ "$DEST" == *":"* ]]; then
    REMOTE=true
    REMOTE_HOST="${DEST%%:*}"
    REMOTE_PATH="${DEST#*:}"
    echo "Remote backup to $REMOTE_HOST:$REMOTE_PATH"
    
    # Create remote directories
    ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_PATH/daily' '$REMOTE_PATH/weekly'"
    
    DAILY_BACKUP="$REMOTE_PATH/daily/backup_$DATE"
    PREV_BACKUP="$REMOTE_PATH/daily/backup_prev"
    
    # Create backup directory
    ssh "$REMOTE_HOST" "mkdir -p '$DAILY_BACKUP'"
    
    # Use previous backup for incremental if exists
    if ssh "$REMOTE_HOST" "[ -d '$PREV_BACKUP' ]"; then
        echo "Using previous backup for incremental sync..."
        rsync -avzL --delete --link-dest="$PREV_BACKUP" "$SOURCE/" "$DEST/daily/backup_$DATE/"
    else
        echo "No previous backup found - creating full backup..."
        rsync -avzL --delete "$SOURCE/" "$DEST/daily/backup_$DATE/"
    fi
    
    # Update previous backup symlink
    ssh "$REMOTE_HOST" "rm -f '$PREV_BACKUP' && ln -s 'backup_$DATE' '$PREV_BACKUP'"
    
    # Cleanup old backups
    ssh "$REMOTE_HOST" "find '$REMOTE_PATH/daily' -maxdepth 1 -type d -name 'backup_*' -mtime +6 -exec rm -rf {} \\;"
    
else
    REMOTE=false
    echo "Local backup to $DEST"
    
    # Use the original local logic
    if [ ! -d "$DEST" ]; then
        mkdir -p "$DEST"
    fi
    
    CURRENT_DIR="$DEST/current"
    DAILY_DIR="$DEST/daily"
    WEEKLY_DIR="$DEST/weekly"
    
    mkdir -p "$DAILY_DIR" "$WEEKLY_DIR"
    
    if [ -d "$CURRENT_DIR" ]; then
        LINK_DEST="--link-dest=$CURRENT_DIR"
    else
        LINK_DEST=""
    fi
    
    DAILY_BACKUP="$DAILY_DIR/backup_$DATE"
    mkdir -p "$DAILY_BACKUP"
    
    rsync -rvL --times --delete $LINK_DEST "$SOURCE/" "$DAILY_BACKUP/"
    
    if [ -d "$CURRENT_DIR" ]; then
        rm -rf "$CURRENT_DIR"
    fi
    ln -s "$DAILY_BACKUP" "$CURRENT_DIR"
    
    # Local cleanup
    find "$DAILY_DIR" -maxdepth 1 -type d -name "backup_*" -mtime +6 -exec rm -rf {} \;
fi

echo "Backup completed successfully!"
echo "Backup location: $DEST/daily/backup_$DATE"