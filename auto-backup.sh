#!/bin/bash

#
# Ultra-Fast Backup Script (Optional Archive Mode)
#


set -euo pipefail
IFS=$'\n\t'

# ========== CONFIGURATION ==========

CONFIG_FILE="${1:-/etc/backup_config.conf}"
echo "[DEBUG] Starting script with config: $CONFIG_FILE"

if [ -f "$CONFIG_FILE" ]; then
    echo "[DEBUG] Loading config file: $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    echo "Config file $CONFIG_FILE not found"
    exit 1
fi

DOMAIN_ID=$(basename "${CONFIG_FILE%.*}")

LOG_FILE="${LOG_FILE_PATH:-"/var/log/backup_${DOMAIN_ID}.log"}"
LOG_DIR=$(dirname "$LOG_FILE")
LOCK_FILE="/var/lock/backup_${DOMAIN_ID}.lock"
MAX_LOG_SIZE=10485760  # 10MB

# ========== DEBUG OUTPUT ==========
echo "[DEBUG] DOMAIN_ID: $DOMAIN_ID"
echo "[DEBUG] LOG_FILE: $LOG_FILE"

# ========== LOG DIRECTORY CREATION ==========
if [ ! -d "$LOG_DIR" ]; then
    echo "[DEBUG] Creating log directory: $LOG_DIR"
    mkdir -p "$LOG_DIR" || {
        echo "❌ Failed to create log directory $LOG_DIR"
        exit 1
    }
fi

# ========== LOG FILE SETUP ==========
exec > >(tee -a "$LOG_FILE") 2>&1

if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt $MAX_LOG_SIZE ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
    echo "[*] Rotated log file to ${LOG_FILE}.1"
fi

# ========== LOCK ==========
if ! (set -o noclobber; echo "$$" > "$LOCK_FILE") 2>/dev/null; then
    echo "Backup already in progress. Exiting..."
    exit 1
fi

trap 'rm -f "$LOCK_FILE"; exit' EXIT INT TERM

# ========== FUNCTIONS ==========

check_disk_space() {
    local required_space="$1"
    local available_space
    available_space=$(df --output=avail "$DEST_DIR" | tail -1)
    if [ "$available_space" -lt $((required_space / 1024)) ]; then
        echo "Not enough disk space in $DEST_DIR. Required: $((required_space / 1024)) KB, Available: $available_space KB"
        return 1
    fi
    return 0
}

verify_backup() {
    local archive_path="$1"
    if tar -tf "$archive_path" &>/dev/null; then
        echo "[*] Archive verification passed"
        return 0
    else
        echo "Archive verification failed"
        return 1
    fi
}

cleanup_backups() {
    local dir="$1"
    local pattern="$2"
    local keep_count="$3"
    local remote_folder="$4"
    local dry_run="$5"
    local is_directory="$6"

    echo "[*] Cleaning up old backups (keep last $keep_count)"

    if [ "$is_directory" = "true" ]; then
        mapfile -t local_files < <(find "$dir" -mindepth 1 -maxdepth 1 -type d | sort -r)
    else
        mapfile -t local_files < <(ls -1t "$dir"/$pattern 2>/dev/null || true)
    fi

    if [ "${#local_files[@]}" -gt "$keep_count" ]; then
        for ((i=keep_count; i<${#local_files[@]}; i++)); do
            echo "   🗑️ Deleting local: ${local_files[$i]}"
            rm -rf "${local_files[$i]}"
        done
    fi

    echo "[*] Cleaning up old remote backups"
    local remote_files
    if [ "$is_directory" = "true" ]; then
        mapfile -t remote_files < <(rclone lsf "$GDRIVE_REMOTE_NAME:$remote_folder" --dirs-only 2>/dev/null | sort -r)
    else
        mapfile -t remote_files < <(rclone lsf "$GDRIVE_REMOTE_NAME:$remote_folder" 2>/dev/null | grep -E '\.tar$' | sort -r)
    fi

    if [ "${#remote_files[@]}" -gt "$keep_count" ]; then
        for ((i=keep_count; i<${#remote_files[@]}; i++)); do
            echo "   🗑️ Deleting remote: ${remote_files[$i]}"
            if [ "$dry_run" != "true" ]; then
                if [ "$is_directory" = "true" ]; then
                    rclone purge "$GDRIVE_REMOTE_NAME:$remote_folder/${remote_files[$i]}"
                else
                    rclone deletefile "$GDRIVE_REMOTE_NAME:$remote_folder/${remote_files[$i]}"
                fi
            else
                echo "   [Dry Run] Would delete ${remote_files[$i]}"
            fi
        done
    fi
}

# ========== MAIN SCRIPT ==========

echo "[*] $(date '+%Y-%m-%d %H:%M:%S') Backup started"

required_vars=("SOURCE_DIR" "DEST_DIR" "GDRIVE_FOLDER_PATH" "KEEP_COUNT" "GDRIVE_REMOTE_NAME")
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "❌ Configuration error: Missing $var"
        exit 1
    fi
done

if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ Source directory $SOURCE_DIR not found"
    exit 1
fi

mkdir -p "$DEST_DIR" || {
    echo "❌ Failed to create $DEST_DIR"
    exit 1
}

ARCHIVE_MODE=${ARCHIVE_MODE:-true}

if [ "$ARCHIVE_MODE" = true ]; then
    required_space=$(du -sb "$SOURCE_DIR" | awk '{print $1}')
    check_disk_space "$required_space" || exit 1

    ARCHIVE_NAME="backup_$(date +%Y%m%d_%H%M%S).tar"
    ARCHIVE_PATH="$DEST_DIR/$ARCHIVE_NAME"
    echo "[*] Creating archive from $SOURCE_DIR"

    START_TIME=$(date +%s)
    tar -cf "$ARCHIVE_PATH" -C "$SOURCE_DIR" .
    TAR_EXIT=$?
    END_TIME=$(date +%s)

    if [ $TAR_EXIT -ne 0 ]; then
        echo "❌ Archive creation failed (exit code $TAR_EXIT)"
        exit 1
    fi

    echo "[*] Archive created in $((END_TIME - START_TIME)) seconds"

    verify_backup "$ARCHIVE_PATH" || exit 1

    echo "[*] Preparing remote destination"
    rclone mkdir "$GDRIVE_REMOTE_NAME:$GDRIVE_FOLDER_PATH" || true

    echo "[*] Starting upload to Google Drive"
    UPLOAD_CMD="rclone copy \"$ARCHIVE_PATH\" \"$GDRIVE_REMOTE_NAME:$GDRIVE_FOLDER_PATH\""
    [ -n "${BWLIMIT:-}" ] && UPLOAD_CMD+=" --bwlimit $BWLIMIT"

    START_UPLOAD=$(date +%s)
    eval "$UPLOAD_CMD" || {
        echo "❌ Upload failed"
        exit 1
    }
    END_UPLOAD=$(date +%s)

    cleanup_backups "$DEST_DIR" "*.tar" "$KEEP_COUNT" "$GDRIVE_FOLDER_PATH" "${DRY_RUN:-false}" "false"

    BACKUP_SIZE=$(du -h "$ARCHIVE_PATH" | cut -f1)
    echo "✅ Backup completed successfully"
    echo "   Size:    $BACKUP_SIZE"
    echo "   Local:   $ARCHIVE_PATH"
    echo "   Remote:  $GDRIVE_FOLDER_PATH/$ARCHIVE_NAME"
    echo "   Runtime: $((END_UPLOAD - START_UPLOAD)) seconds total"

else
    echo "[*] ARCHIVE_MODE=false — Uploading subdirectories in $SOURCE_DIR as-is"

    for dir in "$SOURCE_DIR"/*/; do
        [ -d "$dir" ] || continue
        folder_name=$(basename "$dir")
        echo "[*] Uploading $folder_name"
        rclone mkdir "$GDRIVE_REMOTE_NAME:$GDRIVE_FOLDER_PATH/$folder_name" || true
        rclone copy "$dir" "$GDRIVE_REMOTE_NAME:$GDRIVE_FOLDER_PATH/$folder_name" ${BWLIMIT:+--bwlimit $BWLIMIT} || {
            echo "❌ Failed to upload $folder_name"
            exit 1
        }
    done

    cleanup_backups "$SOURCE_DIR" "" "$KEEP_COUNT" "$GDRIVE_FOLDER_PATH" "${DRY_RUN:-false}" "true"
    echo "✅ Folder upload completed successfully"
fi

exit 0
