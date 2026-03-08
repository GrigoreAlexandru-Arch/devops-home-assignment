#!/bin/bash

LOG_FILE="/var/log/application.log"
ROTATION_THRESHOLD="86400"
ARCHIVAL_THRESHOLD="432000"
DELETION_THRESHOLD="2592000"
ARCHIVE_DIR="/var/backups"

usage() {
    echo "Usage: $0 [-l LOG_FILE] [-r ROTATION_THRESHOLD] [-a ARCHIVAL_THRESHOLD] [-d ARCHIVE_DIR]"
    echo ""
    echo "Description:"
    echo "  A script to rotate active logs without interrupting the application (copytruncate),"
    echo "  and compress older rotated logs into a target archive directory."
    echo ""
    echo "Options:"
    echo "  -l  Path to the active log file (Default: /var/log/application.log)"
    echo "  -r  Seconds before a log is rotated (Default: 86400 / 1 day)"
    echo "  -a  Seconds before a rotated log is archived (Default: 432000 / 5 days)"
    echo "  -t  Seconds before an archive is deleted (Default: 2592000 / 30 days)"
    echo "  -d  Directory to store compressed archives (Default: /var/backups)"
    echo "  -h  Show this help message"
    echo ""
    exit 0
}

while getopts "l:r:a:t:d:h" opt; do
    case $opt in
    l) LOG_FILE="$OPTARG" ;;
    r) ROTATION_THRESHOLD="$OPTARG" ;;
    a) ARCHIVAL_THRESHOLD="$OPTARG" ;;
    t) DELETION_THRESHOLD="$OPTARG" ;;
    d) ARCHIVE_DIR="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
    esac
done

shift $((OPTIND - 1))

TIMESTAMP=$(date +%s)

echo "Started to process $LOG_FILE"
echo "Rotating logs after $ROTATION_THRESHOLD seconds"
echo "Archiving all logs older than $ARCHIVAL_THRESHOLD seconds"
echo "Deleting all logs older than $DELETION_THRESHOLD seconds"

check_log_file() {
    local LOG_FILE="$1"
    if [[ ! -e "$LOG_FILE" ]]; then
        echo "Error: Log file $LOG_FILE doesn't exist." >&2
        return 1
    fi

    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Error: $LOG_FILE is a directory not a file." >&2
        return 2
    fi

    if [[ ! -r "$LOG_FILE" ]]; then
        echo "Error: Log file $LOG_FILE is not readable." >&2
        return 3
    fi

    if [[ ! -w "$LOG_FILE" ]]; then
        echo "Error: Log file $LOG_FILE is not writeable." >&2
        return 4
    fi
}

check_archive_dir() {
    local ARCHIVE_DIR="$1"
    if [[ ! -e "$ARCHIVE_DIR" ]]; then
        echo "Error: Archive directory $ARCHIVE_DIR doesn't exist." >&2
        return 5
    fi

    if [[ -f "$ARCHIVE_DIR" ]]; then
        echo "Error: $ARCHIVE_DIR is not a directory." >&2
        return 6
    fi

    if [[ ! -r "$ARCHIVE_DIR" ]]; then
        echo "Error: Archive directory $ARCHIVE_DIR is not readable" >&2
        return 7
    fi

    if [[ ! -w "$ARCHIVE_DIR" ]]; then
        echo "Error: Archive directory $ARCHIVE_DIR is not writeable" >&2
        return 8
    fi
}

get_latest_rotation_timestamp() {
    local LOG_FILE="$1"
    local LOG_DIR=$(dirname "$LOG_FILE")
    local BASE_NAME=$(basename "$LOG_FILE")
    local MAX_TIMESTAMP=-1

    for FILE_PATH in "$LOG_DIR"/"$BASE_NAME".[0-9]*; do
        if [[ -f "$FILE_PATH" ]]; then
            local CURRENT_TS="${FILE_PATH##*.}"

            if [[ "$CURRENT_TS" -gt "$MAX_TIMESTAMP" ]]; then
                MAX_TIMESTAMP="$CURRENT_TS"
            fi
        fi
    done

    echo "$MAX_TIMESTAMP"
}

should_rotate() {
    local LOG_FILE="$1"
    local ROTATION_THRESHOLD="$2"
    local CURRENT_TIMESTAMP="$3"
    local LATEST_LOG_TIMESTAMP=$(get_latest_rotation_timestamp "$LOG_FILE")

    if [[ "$LATEST_LOG_TIMESTAMP" == "-1" ]]; then
        echo "No rotated logs found. Running script"
        return 0
    fi

    local SECONDS_SINCE_LAST_RUN=$((CURRENT_TIMESTAMP - LATEST_LOG_TIMESTAMP))

    if [[ "$SECONDS_SINCE_LAST_RUN" -lt "$ROTATION_THRESHOLD" ]]; then
        echo "Latest log was rotated $SECONDS_SINCE_LAST_RUN seconds ago, which is lower than $ROTATION_THRESHOLD. Skipping rotation"
        return 1
    else
        echo "Latest log was rotated $SECONDS_SINCE_LAST_RUN seconds ago, which is higher or equal to $ROTATION_THRESHOLD. Running rotation"
        return 0
    fi
}

rotate_log() {
    local LOG_FILE="$1"
    local CURRENT_TIMESTAMP="$2"

    cp "$LOG_FILE" "$LOG_FILE.$CURRENT_TIMESTAMP"

    if [[ "$?" -ne "0" ]]; then
        echo "Error: Could not rotate log. Stopping script" >&2
        return 9
    fi

    : >"$LOG_FILE"

    if [[ "$?" -ne "0" ]]; then
        echo "Error: Could not truncate log. Stopping script" >&2
        return 10
    fi

    return 0
}

archive_rotated_logs() {
    local LOG_FILE="$1"
    local ARCHIVE_DIR="$2"
    local CURRENT_TIMESTAMP="$3"
    local ARCHIVAL_THRESHOLD="$4"

    local LOG_DIR=$(dirname "$LOG_FILE")
    local BASE_NAME=$(basename "$LOG_FILE")

    local FILES_TO_ARCHIVE_FULLPATHS=()
    local FILES_TO_ARCHIVE_BASENAMES=()

    shopt -s nullglob
    local matched_files=("$LOG_DIR"/"$BASE_NAME".[0-9]*)
    shopt -u nullglob

    for FILE in "${matched_files[@]}"; do
        local FILE_BASENAME="${FILE##*/}"
        local FILE_TIMESTAMP="${FILE_BASENAME##*.}"
        
        local FILE_AGE=$((CURRENT_TIMESTAMP - FILE_TIMESTAMP))

        if [[ "$FILE_AGE" -gt "$ARCHIVAL_THRESHOLD" ]]; then
            FILES_TO_ARCHIVE_FULLPATHS+=("$FILE")
            FILES_TO_ARCHIVE_BASENAMES+=("$FILE_BASENAME")
        fi
    done

    if [[ ${#FILES_TO_ARCHIVE_FULLPATHS[@]} -gt 0 ]]; then
        local ARCHIVE_NAME="${ARCHIVE_DIR}/${BASE_NAME}.${CURRENT_TIMESTAMP}.tar.gz"
        echo "Archiving ${#FILES_TO_ARCHIVE_FULLPATHS[@]} old logs to $ARCHIVE_NAME..."

        if tar -czf "$ARCHIVE_NAME" -C "$LOG_DIR" "${FILES_TO_ARCHIVE_BASENAMES[@]}"; then
            echo "Archive successful. Cleaning up original rotated files."
            rm -f "${FILES_TO_ARCHIVE_FULLPATHS[@]}"
        else
            echo "Error: Failed to create archive." >&2
            return 11
        fi
    else
        echo "No logs older than threshold ($ARCHIVAL_THRESHOLD seconds) found to archive."
    fi
}

delete_old_archives() {
    local ARCHIVE_DIR="$1"
    local CURRENT_TIMESTAMP="$2"
    local DELETION_THRESHOLD="$3"
    local BASE_NAME=$(basename "$LOG_FILE")

    echo "Checking for archives older than $DELETION_THRESHOLD seconds..."

    for ARCHIVE in "$ARCHIVE_DIR"/"$BASE_NAME".[0-9]*.tar.gz; do
        if [[ -f "$ARCHIVE" ]]; then
            local FILE_NAME=$(basename "$ARCHIVE")
            local ARCHIVE_TS=$(echo "$FILE_NAME" | grep -oP '\.\K[0-9]+(?=\.tar\.gz)')

            if [[ -n "$ARCHIVE_TS" ]]; then
                local ARCHIVE_AGE=$((CURRENT_TIMESTAMP - ARCHIVE_TS))
                if [[ "$ARCHIVE_AGE" -gt "$DELETION_THRESHOLD" ]]; then
                    echo "Deleting expired archive: $FILE_NAME"
                    rm -f "$ARCHIVE"
                fi
            fi
        fi
    done
}

check_log_file "$LOG_FILE" || exit $?
check_archive_dir "$ARCHIVE_DIR" || exit $?

if should_rotate "$LOG_FILE" "$ROTATION_THRESHOLD" "$TIMESTAMP"; then
    rotate_log "$LOG_FILE" "$TIMESTAMP" || exit $?
fi

archive_rotated_logs "$LOG_FILE" "$ARCHIVE_DIR" "$TIMESTAMP" "$ARCHIVAL_THRESHOLD" || exit $?

delete_old_archives "$ARCHIVE_DIR" "$TIMESTAMP" "$DELETION_THRESHOLD" || exit $?

echo "Script finished successfully"
