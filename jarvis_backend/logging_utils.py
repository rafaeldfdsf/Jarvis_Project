from __future__ import annotations

from datetime import datetime, timezone
import json
import logging
from typing import Any


def configure_logging(level: str = "INFO") -> None:
    if logging.getLogger().handlers:
        logging.getLogger().setLevel(level)
        return

    logging.basicConfig(level=level, format="%(message)s")


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)


def log_event(logger: logging.Logger, level: int, event: str, **fields: Any) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": logging.getLevelName(level),
        "logger": logger.name,
        "event": event,
        **fields,
    }
    logger.log(level, json.dumps(payload, ensure_ascii=False, default=str))
