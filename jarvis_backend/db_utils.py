"""Helpers comuns para acesso SQLite do backend."""

from __future__ import annotations

import sqlite3

from config import DB_FILE


def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_FILE, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn
