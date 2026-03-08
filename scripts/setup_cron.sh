#!/bin/bash

SCRIPT_PATH=""
LOG_FILE="/var/log/application.log"
ROTATION_THRESHOLD="86400"
ARCHIVAL_THRESHOLD="432000"
DELETION_THRESHOLD="2592000"
ARCHIVE_DIR="/var/backups"
CRON_SCHEDULE="0 0 * * *"
CRON_LOG="/var/log/log_rotation_cron.log"
JOB_TAG="# LOG_ROTATION_TASK"

usage() {
    echo "Usage: $0 -s <script_path> [-l <log_file>] [-r <rotation_threshold>] [-a <archival_threshold>] [-d <archive_dir>] [-c <cron_schedule>]"
    echo "Options:"
    echo "  -s  Path to the log rotation script (Required)"
    echo "  -l  Log file path (Default: /var/log/application.log)"
    echo "  -r  Rotation threshold in seconds (Default: 86400 = 1 day)"
    echo "  -a  Archival threshold in seconds (Default: 432000 = 5 days)"
    echo "  -t  Deletion threshol in seconds (Default: 2592000 = 30 days)"
    echo "  -d  Archive directory (Default: /var/backups)"
    echo "  -c  Cron schedule expression (Default: '0 0 * * *')"
    echo "  -h  Show this help message"
    exit 1
}

check_permissions_and_paths() {
    local s_path="$1"
    local a_dir="$2"

    if [[ ! -f "$s_path" ]]; then
        echo "Error: Script file '$s_path' does not exist." >&2
        exit 1
    fi

    if [[ ! -x "$s_path" ]]; then
        echo "Error: Script '$s_path' is not executable. Please run 'chmod +x' on it." >&2
        exit 1
    fi

    if [[ ! -d "$a_dir" ]]; then
        echo "Error: Archive directory '$a_dir' does not exist." >&2
        exit 1
    fi

    if [[ ! -w "$a_dir" ]]; then
        echo "Error: No write permission for archive directory '$a_dir'." >&2
        exit 1
    fi
}

apply_cron_job() {
    local schedule="$1"
    local s_path="$2"
    local l_file="$3"
    local r_thresh="$4"
    local a_thresh="$5"
    local d_thresh="$6"
    local a_dir="$7"
    local c_log="$8"
    local tag="$9"

    local cmd="/usr/bin/flock -n /tmp/log_rotation.lock $s_path -l $l_file -r $r_thresh -a $a_thresh -t $d_thresh -d $a_dir >> $c_log 2>&1"
    local full_job="$schedule $cmd $tag"

    echo "Updating crontab for $l_file..."

    if (
        crontab -l 2>/dev/null | grep -v "$tag" || true
        echo "$full_job"
    ) | crontab -; then
        echo "Success: Cron job configured."
    else
        echo "Error: Failed to write to crontab." >&2
        exit 1
    fi
}

while getopts "s:l:r:a:t:d:c:h" opt; do
    case $opt in
    s) SCRIPT_PATH="$OPTARG" ;;
    l) LOG_FILE="$OPTARG" ;;
    r) ROTATION_THRESHOLD="$OPTARG" ;;
    a) ARCHIVAL_THRESHOLD="$OPTARG" ;;
    t) DELETION_THRESHOLD="$OPTARG" ;;
    d) ARCHIVE_DIR="$OPTARG" ;;
    c) CRON_SCHEDULE="$OPTARG" ;;
    *) usage ;;
    esac
done

if [[ -z "$SCRIPT_PATH" ]]; then
    echo "Error: Script path (-s) is required." >&2
    usage
fi

check_permissions_and_paths "$SCRIPT_PATH" "$ARCHIVE_DIR"
apply_cron_job "$CRON_SCHEDULE" "$SCRIPT_PATH" "$LOG_FILE" "$ROTATION_THRESHOLD" "$ARCHIVAL_THRESHOLD" "$DELETION_THRESHOLD" "$ARCHIVE_DIR" "$CRON_LOG" "$JOB_TAG"
