"""Persistencia local de dispositivos Home Assistant e aliases."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
import unicodedata

from db_utils import connect


def _connect():
    conn = connect()
    return conn


def _table_columns(cursor, table_name: str) -> set[str]:
    cursor.execute(f"PRAGMA table_info({table_name})")
    return {row["name"] for row in cursor.fetchall()}


def _ensure_devices_schema(cursor) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS home_assistant_devices (
            user_id TEXT,
            entity_id TEXT NOT NULL,
            domain TEXT NOT NULL,
            friendly_name TEXT NOT NULL,
            alias TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL DEFAULT '',
            attributes_json TEXT NOT NULL DEFAULT '{}',
            last_seen_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (user_id, entity_id)
        )
        """
    )

    columns = _table_columns(cursor, "home_assistant_devices")
    if "user_id" in columns:
        return

    cursor.execute("ALTER TABLE home_assistant_devices RENAME TO home_assistant_devices_legacy")
    cursor.execute(
        """
        CREATE TABLE home_assistant_devices (
            user_id TEXT,
            entity_id TEXT NOT NULL,
            domain TEXT NOT NULL,
            friendly_name TEXT NOT NULL,
            alias TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL DEFAULT '',
            attributes_json TEXT NOT NULL DEFAULT '{}',
            last_seen_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (user_id, entity_id)
        )
        """
    )
    cursor.execute(
        """
        INSERT INTO home_assistant_devices (
            user_id, entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
        )
        SELECT NULL, entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
        FROM home_assistant_devices_legacy
        """
    )
    cursor.execute("DROP TABLE home_assistant_devices_legacy")


def init_devices_db() -> None:
    conn = _connect()
    cursor = conn.cursor()
    _ensure_devices_schema(cursor)
    conn.commit()
    conn.close()


def _user_filter_sql(user_id: str | None) -> tuple[str, tuple[object, ...]]:
    if user_id is None:
        return "user_id IS NULL", ()
    return "user_id = ?", ((user_id or "").strip(),)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def sync_devices(domain: str | None = None, user_id: str | None = None) -> list[dict[str, Any]]:
    init_devices_db()
    from home_assistant.service import list_entities

    entities = list_entities(domain=domain, user_id=user_id)
    now = _now_iso()
    clean_user_id = (user_id or "").strip() or None

    conn = _connect()
    cursor = conn.cursor()

    for entity in entities:
        cursor.execute(
            "DELETE FROM home_assistant_devices WHERE user_id IS ? AND entity_id = ?",
            (clean_user_id, entity["entity_id"]),
        )
        cursor.execute(
            """
            INSERT INTO home_assistant_devices (
                user_id, entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
            )
            VALUES (?, ?, ?, ?, '', ?, ?, ?, ?)
            """,
            (
                clean_user_id,
                entity["entity_id"],
                entity["domain"],
                str(entity.get("friendly_name") or entity["entity_id"]).strip(),
                str(entity.get("state") or "").strip(),
                json_dumps(entity.get("attributes") or {}),
                now,
                now,
            ),
        )

    conn.commit()
    conn.close()
    return list_devices(domain=domain, user_id=user_id)


def list_devices(domain: str | None = None, user_id: str | None = None) -> list[dict[str, Any]]:
    init_devices_db()
    conn = _connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)

    clean_domain = (domain or "").strip().lower()
    if clean_domain:
        cursor.execute(
            f"""
            SELECT entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
            FROM home_assistant_devices
            WHERE {where_sql} AND domain = ?
            ORDER BY domain, alias COLLATE NOCASE, friendly_name COLLATE NOCASE, entity_id COLLATE NOCASE
            """,
            (*params, clean_domain),
        )
    else:
        cursor.execute(
            f"""
            SELECT entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
            FROM home_assistant_devices
            WHERE {where_sql}
            ORDER BY domain, alias COLLATE NOCASE, friendly_name COLLATE NOCASE, entity_id COLLATE NOCASE
            """,
            params,
        )

    rows = cursor.fetchall()
    conn.close()
    return [_row_to_device(row) for row in rows]


def update_device_alias(entity_id: str, alias: str, user_id: str | None = None) -> dict[str, Any]:
    init_devices_db()
    now = _now_iso()
    conn = _connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"""
        UPDATE home_assistant_devices
        SET alias = ?, updated_at = ?
        WHERE entity_id = ? AND {where_sql}
        """,
        (alias.strip(), now, entity_id.strip(), *params),
    )
    updated = cursor.rowcount > 0
    conn.commit()
    conn.close()
    if not updated:
        raise KeyError(f"Dispositivo nao encontrado: {entity_id}")
    return get_device(entity_id, user_id=user_id) or {}


def delete_device(entity_id: str, user_id: str | None = None) -> bool:
    init_devices_db()
    conn = _connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"DELETE FROM home_assistant_devices WHERE entity_id = ? AND {where_sql}",
        (entity_id.strip(), *params),
    )
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def clear_devices(user_id: str | None = None) -> int:
    init_devices_db()
    conn = _connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(f"DELETE FROM home_assistant_devices WHERE {where_sql}", params)
    deleted_count = cursor.rowcount
    conn.commit()
    conn.close()
    return deleted_count


def get_device(entity_id: str, user_id: str | None = None) -> dict[str, Any] | None:
    init_devices_db()
    conn = _connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"""
        SELECT entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
        FROM home_assistant_devices
        WHERE entity_id = ? AND {where_sql}
        """,
        (entity_id.strip(), *params),
    )
    row = cursor.fetchone()
    conn.close()
    return _row_to_device(row) if row else None


def device_alias_map(user_id: str | None = None) -> dict[str, dict[str, str]]:
    devices = list_devices(user_id=user_id)
    result: dict[str, dict[str, str]] = {}
    for device in devices:
        alias = str(device.get("alias") or "").strip()
        if not alias:
            continue
        result[device["entity_id"]] = {
            "alias": alias,
            "friendly_name": device["friendly_name"],
            "domain": device["domain"],
        }
    return result


def resolve_device_reference(reference: str, domain: str | None = None, user_id: str | None = None) -> dict[str, Any] | None:
    clean_reference = (reference or "").strip()
    if not clean_reference:
        return None

    devices = list_devices(domain=domain, user_id=user_id)
    if not devices:
        return None

    clean_domain = (domain or "").strip().lower()

    for device in devices:
        if device["entity_id"].strip().lower() == clean_reference.lower():
            return device

    normalized_reference = _normalize(clean_reference)
    candidates: list[tuple[int, dict[str, Any]]] = []

    for device in devices:
        score = _match_score(device, normalized_reference, clean_domain)
        if score > 0:
            candidates.append((score, device))

    if not candidates:
        return None

    candidates.sort(
        key=lambda item: (
            -item[0],
            _duplicate_penalty(item[1]),
            0 if str(item[1].get("state") or "").lower() in {"on", "playing"} else 1,
            item[1]["entity_id"].lower(),
        )
    )
    return candidates[0][1]


def _row_to_device(row) -> dict[str, Any]:
    return {
        "entity_id": row["entity_id"],
        "domain": row["domain"],
        "friendly_name": row["friendly_name"],
        "alias": row["alias"],
        "state": row["state"],
        "attributes": json_loads(row["attributes_json"]),
        "last_seen_at": row["last_seen_at"],
        "updated_at": row["updated_at"],
    }


def _normalize(value: str) -> str:
    normalized = unicodedata.normalize("NFD", value.lower().strip())
    clean = "".join(ch for ch in normalized if unicodedata.category(ch) != "Mn")
    return " ".join(clean.replace("_", " ").replace("-", " ").split())


def _match_score(device: dict[str, Any], reference: str, domain: str) -> int:
    if domain and str(device.get("domain") or "").lower() != domain:
        return 0

    alias = _normalize(str(device.get("alias") or ""))
    friendly_name = _normalize(str(device.get("friendly_name") or ""))
    entity_id = _normalize(str(device.get("entity_id") or ""))

    if alias and alias == reference:
        return 500
    if friendly_name == reference:
        return 400
    if entity_id == reference:
        return 300
    if alias and reference in alias:
        return 250
    if reference in friendly_name:
        return 200
    if reference in entity_id:
        return 100
    return 0


def _duplicate_penalty(device: dict[str, Any]) -> int:
    entity_id = str(device.get("entity_id") or "").lower()
    return 1 if entity_id.endswith("_2") or entity_id.endswith("_3") or entity_id.endswith("_4") else 0


def json_dumps(value: Any) -> str:
    import json

    return json.dumps(value, ensure_ascii=False)


def json_loads(value: str) -> Any:
    import json

    try:
        return json.loads(value or "{}")
    except json.JSONDecodeError:
        return {}
