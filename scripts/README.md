# Log Rotation and Automation

This repository contains a suite of scripts designed to simulate application logging, rotate active logs without interrupting the application, archive older logs, and enforce retention policies via an automated cron job.

---

## How the Script Works

The solution is divided into three primary components:

1. **`simulate_logging.py`**: A Python script that acts as the target application. It continuously writes log entries to a designated file (`/var/log/application.log` by default) at a specified interval.
2. **`archive_logs.sh`**: A Bash script responsible for the core log management logic. It checks file permissions and existence, rotates the active log, archives older rotated logs, and purges expired archives. It uses a "copytruncate" method (`cp` followed by `: >`), allowing the application to continue writing to the active file descriptor without requiring an application restart.
3. **`setup_chron.sh`**: A Bash script that automates the deployment of `archive_logs.sh`. It validates paths, checks necessary permissions, and registers a cron job wrapped with `flock` to guarantee idempotent execution and prevent overlapping runs.

---

## Log Retention and Archival Logic

The script evaluates file ages based on timestamps appended to the file names during rotation. The lifecycle is defined by three configurable thresholds:

- **Rotation Threshold (Default: 86,400 seconds / 1 day):** The script checks the timestamp of the most recently rotated log. If the elapsed time since that timestamp exceeds the rotation threshold, the active log is copied to a new file (e.g., `application.log.<TIMESTAMP>`), and the active log is truncated to zero bytes.
- **Archival Threshold (Default: 432,000 seconds / 5 days):** The script scans all uncompressed rotated logs. Any log file whose age (current time minus its filename timestamp) exceeds this threshold is bundled into a compressed tarball (`.tar.gz`) in the designated backup directory (`/var/backups` by default). The original uncompressed rotated logs are then deleted.
- **Deletion Threshold (Default: 2,592,000 seconds / 30 days):** The script scans the backup directory for compressed archives. If an archive's age exceeds this threshold, it is permanently deleted to free up disk space.

---

## Cron Schedule Used

By default, the `setup_chron.sh` script configures the following cron schedule:

```cron
0 0 * * *

```

This expression dictates that the log rotation script runs **daily at midnight**.

**Execution Details:**

- **Locking:** The cron job utilizes `/usr/bin/flock -n /tmp/log_rotation.lock` to ensure only one instance of the script runs at a time.
- **Logging:** Output and errors from the cron execution are redirected to `/var/log/log_rotation_cron.log` for auditing purposes.

---

## How to Test the Script Manually

To verify the logic without waiting for standard daily intervals, you can override the default thresholds using the script's command-line flags.

**Step 1: Create required directories and set permissions**

```bash
sudo mkdir -p /var/log /var/backups
sudo touch /var/log/application.log
sudo chmod 666 /var/log/application.log
sudo chmod 777 /var/backups

```

**Step 2: Start the log simulation in the background**

```bash
python3 simulate_logging.py -i 0.5 &

```

**Step 3: Trigger a manual rotation**
Wait a few seconds, then execute the archive script with shortened thresholds (e.g., rotate every 5 seconds, archive after 10 seconds, delete after 20 seconds).

```bash
./archive_logs.sh -r 5 -a 10 -t 20

```

_Verify that `application.log.<TIMESTAMP>` has been created in `/var/log/` and `application.log` has been truncated._

**Step 4: Trigger archival**
Wait at least 10 seconds, then run the script again.

```bash
./archive_logs.sh -r 5 -a 10 -t 20

```

_Verify that a `.tar.gz` file appears in `/var/backups/` and the older rotated logs in `/var/log/` are removed._

**Step 5: Trigger deletion**
Wait at least 20 seconds, then run the script a final time.

```bash
./archive_logs.sh -r 5 -a 10 -t 20

```

_Verify that the expired `.tar.gz` archive in `/var/backups/` has been deleted._

**Step 6: Stop the simulation**

```bash
pkill -f simulate_logging.py

```
