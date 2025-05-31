# Ultra-Fast Backup Script

A robust and configurable Bash backup script with optional archive mode, supporting local and Google Drive remote backups.  
Designed for reliability, efficiency, and easy automation.

---

## Features

- Backup directories as compressed tar archives or upload directories as-is
- Automatic cleanup of old backups (local and remote)
- Google Drive integration via [rclone](https://rclone.org/)
- Disk space check before archive creation
- Log rotation and detailed logging
- Dry run mode for testing without making changes
- Bandwidth limiting support for uploads
- Lock file mechanism to prevent concurrent executions

---

## Requirements

- Bash 4+
- `rclone` (configured with Google Drive remote)
- `tar`
- Disk space for archiving (if archive mode enabled)

---

## Installation

1. Clone this repository:
   ```bash
   git clon https://github.com/sonill/Ultra-Fast-Backup-Script.git
   cd Ultra-Fast-Backup-Script
