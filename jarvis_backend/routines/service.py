"""Persistencia e execucao de rotinas do assistente."""

from __future__ import annotations

from datetime import datetime, timezone
import json
from typing import Any
from uuid import uuid4

from db_utils import connect
from home_assistant.service import call_service


def _connect():
    conn = connect()
    return conn


def _table_columns(cursor, table_name: str) -> set[str]:
    cursor.execute(f"PRAGMA table_info({table_name})")
    return {row["name"] for row in cursor.fetchall()}


def _ensure_routines_schema(cursor) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS routines (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            trigger_text TEXT NOT NULL DEFAULT '',
            actions_json TEXT NOT NULL DEFAULT '[]',
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )

    columns = _table_columns(cursor, "routines")
    if "user_id" in columns:
        return

    cursor.execute("ALTER TABLE routines RENAME TO routines_legacy")
    cursor.execute(
        """
        CREATE TABLE routines (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            trigger_text TEXT NOT NULL DEFAULT '',
            actions_json TEXT NOT NULL DEFAULT '[]',
            enabled INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    cursor.execute(
        """
        INSERT INTO routines (
            id, user_id, name, description, trigger_text, actions_json, enabled, created_at, updated_at
        )
        SELECT id, NULL, name, description, trigger_text, actions_json, enabled, created_at, updated_at
        FROM routines_legacy
        """
    )
    cursor.execute("DROP TABLE routines_legacy")


def init_routines_db() -> None:
    conn = _connect()
    cursor = conn.cursor()
    _ensure_routines_schema(cursor)
    conn.commit()
    conn.close()


def _user_filter_sql(user_id: str | None) -> tuple[str, tuple[object, ...]]:
    if user_id is None:
        return "user_id IS NULL", ()
    return "user_id = ?", ((user_id or "").strip(),)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _normalize_actions(actions: list[dict[str, Any]] | None) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for action in actions or []:
        if not isinstance(action, dict):
            continue

        action_type = str(action.get("type") or "").strip()
        if not action_type:
            continue

        item = {"type": action_type}
        for key in (
            "label",
            "domain",
            "service",
            "entity_id",
            "target",
            "message",
            "text",
        ):
            value = action.get(key)
            if isinstance(value, str) and value.strip():
                item[key] = value.strip()

        service_data = action.get("service_data")
        if isinstance(service_data, dict):
            item["service_data"] = service_data

        normalized.append(item)

    return normalized


def _row_to_routine(row) -> dict[str, Any]:
    actions = json.loads(row["actions_json"] or "[]")
    if not isinstance(actions, list):
        actions = []

    return {
        "id": row["id"],
        "name": row["name"],
        "description": row["description"],
        "trigger_text": row["trigger_text"],
        "actions": actions,
        "enabled": bool(row["enabled"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def list_routines(user_id: str | None = None) -> list[dict[str, Any]]:
    init_routines_db()
    conn = _connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"""
        SELECT id, name, description, trigger_text, actions_json, enabled, created_at, updated_at
        FROM routines
        WHERE {where_sql}
        ORDER BY updated_at DESC, name COLLATE NOCASE ASC
        """,
        params,
    )
    rows = cursor.fetchall()
    conn.close()
    return [_row_to_routine(row) for row in rows]


def get_routine(routine_id: str, user_id: str | None = None) -> dict[str, Any] | None:
    init_routines_db()
    conn = _connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"""
        SELECT id, name, description, trigger_text, actions_json, enabled, created_at, updated_at
        FROM routines
        WHERE id = ? AND {where_sql}
        """,
        (routine_id, *params),
    )
    row = cursor.fetchone()
    conn.close()
    return _row_to_routine(row) if row else None


def create_routine(
    *,
    name: str,
    description: str = "",
    trigger_text: str = "",
    actions: list[dict[str, Any]] | None = None,
    enabled: bool = True,
    user_id: str | None = None,
) -> dict[str, Any]:
    init_routines_db()
    clean_name = name.strip()
    if not clean_name:
        raise ValueError("O nome da rotina e obrigatorio.")

    normalized_actions = _normalize_actions(actions)
    routine_id = str(uuid4())
    now = _now_iso()

    conn = _connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        INSERT INTO routines (
            id, user_id, name, description, trigger_text, actions_json, enabled, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            routine_id,
            (user_id or "").strip() or None,
            clean_name,
            description.strip(),
            trigger_text.strip(),
            json.dumps(normalized_actions, ensure_ascii=False),
            1 if enabled else 0,
            now,
            now,
        ),
    )
    conn.commit()
    conn.close()
    return get_routine(routine_id, user_id=user_id) or {}


def update_routine(
    routine_id: str,
    *,
    name: str,
    description: str = "",
    trigger_text: str = "",
    actions: list[dict[str, Any]] | None = None,
    enabled: bool = True,
    user_id: str | None = None,
) -> dict[str, Any]:
    init_routines_db()
    clean_name = name.strip()
    if not clean_name:
        raise ValueError("O nome da rotina e obrigatorio.")

    normalized_actions = _normalize_actions(actions)
    now = _now_iso()
    where_sql, params = _user_filter_sql(user_id)

    conn = _connect()
    cursor = conn.cursor()
    cursor.execute(
        f"""
        UPDATE routines
        SET name = ?, description = ?, trigger_text = ?, actions_json = ?, enabled = ?, updated_at = ?
        WHERE id = ? AND {where_sql}
        """,
        (
            clean_name,
            description.strip(),
            trigger_text.strip(),
            json.dumps(normalized_actions, ensure_ascii=False),
            1 if enabled else 0,
            now,
            routine_id,
            *params,
        ),
    )
    updated = cursor.rowcount > 0
    conn.commit()
    conn.close()
    if not updated:
        raise KeyError(f"Rotina nao encontrada: {routine_id}")
    return get_routine(routine_id, user_id=user_id) or {}


def delete_routine(routine_id: str, user_id: str | None = None) -> bool:
    init_routines_db()
    conn = _connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"DELETE FROM routines WHERE id = ? AND {where_sql}",
        (routine_id, *params),
    )
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def run_routine(routine_id: str, user_id: str | None = None) -> dict[str, Any]:
    init_routines_db()
    routine = get_routine(routine_id, user_id=user_id)
    if not routine:
        raise KeyError(f"Rotina nao encontrada: {routine_id}")

    results = []
    for index, action in enumerate(routine.get("actions") or [], start=1):
        action_type = action.get("type")
        if action_type == "home_assistant_service":
            results.append(
                {
                    "step": index,
                    "type": action_type,
                    "ok": True,
                    "data": call_service(
                        action.get("domain", ""),
                        action.get("service", ""),
                        entity_id=action.get("entity_id"),
                        service_data=action.get("service_data"),
                        user_id=user_id,
                    ),
                }
            )
            continue

        results.append(
            {
                "step": index,
                "type": action_type,
                "ok": False,
                "data": f"Tipo de acao nao suportado: {action_type}",
            }
        )

    return {
        "routine_id": routine_id,
        "routine_name": routine["name"],
        "results": results,
    }
