import logging
import sys
from collections import deque


class MemoryLogHandler(logging.Handler):
    """Thread-safe ring buffer log handler to expose live logs inside the GUI."""

    def __init__(self, capacity: int = 1500) -> None:
        super().__init__()
        self.buffer: deque[str] = deque(maxlen=capacity)

    def emit(self, record: logging.LogRecord) -> None:
        try:
            msg = self.format(record)
            self.buffer.append(msg)
        except Exception:
            self.handleError(record)

    def get_logs_text(self) -> str:
        return "\n".join(self.buffer)

    def clear(self) -> None:
        self.buffer.clear()


GLOBAL_MEMORY_HANDLER = MemoryLogHandler()


def setup_cli_logging(debug: bool = True, verbose: bool = False) -> logging.Logger:
    level = logging.DEBUG if (debug or verbose) else logging.INFO
    log_format = "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    date_format = "%H:%M:%S"

    logger = logging.getLogger("DMAN")
    logger.setLevel(level)

    while logger.handlers:
        logger.handlers.pop()

    formatter = logging.Formatter(log_format, datefmt=date_format)

    stdout_handler = logging.StreamHandler(sys.stdout)
    stdout_handler.setLevel(level)
    stdout_handler.setFormatter(formatter)
    logger.addHandler(stdout_handler)

    GLOBAL_MEMORY_HANDLER.setLevel(level)
    GLOBAL_MEMORY_HANDLER.setFormatter(formatter)
    logger.addHandler(GLOBAL_MEMORY_HANDLER)

    return logger
