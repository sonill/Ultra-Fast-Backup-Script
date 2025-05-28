# Usage:
#   sudo ./backup.sh [config_file]
#
# Arguments:
#   config_file    Optional path to a configuration file (default: /etc/backup_config.conf)
#
# Description:
#   This script performs backups of a specified source directory to a local destination
#   and optionally uploads the backup to Google Drive using rclone.
#   It supports two modes:
#     - ARCHIVE_MODE=true  (default): Creates a tar archive of SOURCE_DIR and uploads it.
#     - ARCHIVE_MODE=false : Uploads subdirectories individually without archiving.
#
# Configuration:
#   The configuration file must define the following variables:
#     SOURCE_DIR           - Directory to back up
#     DEST_DIR             - Local backup destination directory
#     GDRIVE_REMOTE_NAME   - Name of the rclone remote configured for Google Drive
#     GDRIVE_FOLDER_PATH   - Google Drive folder path where backups will be stored
#     KEEP_COUNT           - Number of backups to keep locally and remotely
#     LOG_FILE_PATH        - (Optional) Path for the log file (default based on config file name)
#     ARCHIVE_MODE         - (Optional) true or false, whether to create tar archives (default: true)
#     BWLIMIT              - (Optional) Bandwidth limit for rclone upload (e.g., 1M, 500k)
#     DRY_RUN              - (Optional) Set to "true" to simulate deletions without removing files
#
# Features:
#   - Log rotation if log file exceeds 10MB
#   - Locking to prevent concurrent runs
#   - Disk space check before archiving
#   - Verification of tar archive integrity
#   - Cleanup of old backups both locally and remotely via rclone
#
# Requirements:
#   - bash shell
#   - tar utility
#   - rclone configured with Google Drive remote
#
# Example config file (/etc/backup_config.conf):
#   SOURCE_DIR="/var/www/html"
#   DEST_DIR="/backups"
#   GDRIVE_REMOTE_NAME="gdrive"
#   GDRIVE_FOLDER_PATH="backups/site1"
#   KEEP_COUNT=5
#   ARCHIVE_MODE=true
#   BWLIMIT="2M"
#   DRY_RUN="false"
#
# Run with default config:
#   sudo ./backup.sh
#
# Run with custom config:
#   sudo ./backup.sh /path/to/custom_backup.conf
#
# Exit Codes:
#   0 - Success
#   1 - Failure (configuration or runtime error)
#
