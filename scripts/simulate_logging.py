from pathlib import Path
import random
from argparse import ArgumentParser, Namespace
import logging
import time
import sys


def configure_parameters() -> Namespace:
    args_parser = ArgumentParser(
        description="Simulate continuous logging using FileHandler."
    )
    args_parser.add_argument(
        "-l",
        "--log_path",
        type=Path,
        default=Path("/var/log/application.log"),
        help="Path where the log file will be generated",
    )
    args_parser.add_argument(
        "-i",
        "--write_interval",
        type=float,
        default=1.0,
        help="Interval between log writes in seconds",
    )
    return args_parser.parse_args()


def setup_loggers(log_path: Path) -> tuple[logging.Logger, logging.Logger]:
    """Configures and returns a console logger and a file logger."""

    log_path.parent.mkdir(parents=True, exist_ok=True)

    console_logger = logging.getLogger("SystemInfo")
    console_logger.setLevel(logging.DEBUG)
    console_handler = logging.StreamHandler(sys.stdout)
    console_formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
    console_handler.setFormatter(console_formatter)

    if not console_logger.handlers:
        console_logger.addHandler(console_handler)

    file_logger = logging.getLogger("AppLogger")
    file_logger.setLevel(logging.INFO)
    file_handler = logging.FileHandler(log_path, mode="a")
    file_formatter = logging.Formatter(
        fmt="%(asctime)s - %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
    )
    file_handler.setFormatter(file_formatter)

    if not file_logger.handlers:
        file_logger.addHandler(file_handler)

    return console_logger, file_logger


def write_logs(
    write_interval: float, console_logger: logging.Logger, file_logger: logging.Logger
) -> None:
    try:
        while True:
            file_logger.info(f"Periodic log entry generated: {random.uniform(0,100)}")
            time.sleep(write_interval)

    except KeyboardInterrupt:
        console_logger.info("Keyboard interrupt received. Exiting log loop.")


def main() -> None:
    args = configure_parameters()
    log_path: Path = args.log_path
    write_interval: float = args.write_interval

    try:
        console_logger, file_logger = setup_loggers(log_path)
    except PermissionError:
        print(
            f"Permission denied: Cannot write to {log_path.absolute()}", file=sys.stderr
        )
        sys.exit(1)

    console_logger.info(
        f"Starting to write logs to {log_path.absolute()} every {write_interval} seconds"
    )

    write_logs(write_interval, console_logger, file_logger)

    console_logger.info("Log script finished.")


if __name__ == "__main__":
    main()
