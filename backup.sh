#!/bin/bash

set -e

usage() {
    echo "Usage: $0 <source_directory> <destination_directory>"
    echo "Example: $0 /home/user/documents /backup/location"
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
    echo "Using existing backup as base for incremental sync..."
    LINK_DEST="--link-dest=$CURRENT_DIR"
else
    echo "No previous backup found - creating full backup..."
    LINK_DEST=""
fi

DAILY_BACKUP="$DAILY_DIR/backup_$DATE"
mkdir -p "$DAILY_BACKUP"

echo "Syncing files with rsync..."
rsync -rvL --times --delete $LINK_DEST "$SOURCE/" "$DAILY_BACKUP/"

if [ -d "$CURRENT_DIR" ]; then
    rm -rf "$CURRENT_DIR"
fi
ln -s "$DAILY_BACKUP" "$CURRENT_DIR"

echo "Daily backup created: $DAILY_BACKUP"

if [ $(date +%u) -eq 7 ]; then
    echo "Sunday detected - creating weekly backup"
    WEEKLY_BACKUP="$WEEKLY_DIR/weekly_$WEEK"
    cp -al "$DAILY_BACKUP" "$WEEKLY_BACKUP"
    
    echo "Compressing weekly backup..."
    tar -czf "$WEEKLY_BACKUP.tar.gz" -C "$WEEKLY_DIR" "$(basename "$WEEKLY_BACKUP")"
    rm -rf "$WEEKLY_BACKUP"
    echo "Weekly backup created: $WEEKLY_BACKUP.tar.gz"
fi

echo "Cleaning up old backups..."

find "$DAILY_DIR" -maxdepth 1 -type d -name "backup_*" -mtime +6 -exec rm -rf {} \;
echo "Removed daily backups older than 7 days"

find "$WEEKLY_DIR" -name "weekly_*.tar.gz" -mtime +83 -delete
echo "Removed weekly backups older than 12 weeks"

BACKUP_SIZE=$(du -sh "$DAILY_BACKUP" | cut -f1)
echo "Backup completed successfully!"
echo "Backup size: $BACKUP_SIZE"
echo "Daily backup location: $DAILY_BACKUP"
echo "Current backup symlink: $CURRENT_DIR"