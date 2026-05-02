"""Persistencia local de dispositivos Home Assistant e aliases."""

from __future__ import annotations

from datetime import datetime, timezone
import sqlite3
from typing import Any
import unicodedata

from config import DB_FILE


def _connect():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn


def init_devices_db() -> None:
    conn = _connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS home_assistant_devices (
            entity_id TEXT PRIMARY KEY,
            domain TEXT NOT NULL,
            friendly_name TEXT NOT NULL,
            alias TEXT NOT NULL DEFAULT '',
            state TEXT NOT NULL DEFAULT '',
            attributes_json TEXT NOT NULL DEFAULT '{}',
            last_seen_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    conn.commit()
    conn.close()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def sync_devices(domain: str | None = None) -> list[dict[str, Any]]:
    init_devices_db()
    from home_assistant.service import list_entities

    entities = list_entities(domain=domain)
    now = _now_iso()

    conn = _connect()
    cursor = conn.cursor()

    for entity in entities:
        cursor.execute(
            """
            INSERT INTO home_assistant_devices (
                entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
            )
            VALUES (?, ?, ?, '', ?, ?, ?, ?)
            ON CONFLICT(entity_id) DO UPDATE SET
                domain = excluded.domain,
                friendly_name = excluded.friendly_name,
                state = excluded.state,
                attributes_json = excluded.attributes_json,
                last_seen_at = excluded.last_seen_at,
                updated_at = excluded.updated_at
            """,
            (
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
    return list_devices(domain=domain)


def list_devices(domain: str | None = None) -> list[dict[str, Any]]:
    init_devices_db()
    conn = _connect()
    cursor = conn.cursor()

    clean_domain = (domain or "").strip().lower()
    if clean_domain:
        cursor.execute(
            """
            SELECT entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
            FROM home_assistant_devices
            WHERE domain = ?
            ORDER BY domain, alias COLLATE NOCASE, friendly_name COLLATE NOCASE, entity_id COLLATE NOCASE
            """,
            (clean_domain,),
        )
    else:
        cursor.execute(
            """
            SELECT entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
            FROM home_assistant_devices
            ORDER BY domain, alias COLLATE NOCASE, friendly_name COLLATE NOCASE, entity_id COLLATE NOCASE
            """
        )

    rows = cursor.fetchall()
    conn.close()
    return [_row_to_device(row) for row in rows]


def update_device_alias(entity_id: str, alias: str) -> dict[str, Any]:
    init_devices_db()
    now = _now_iso()
    conn = _connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        UPDATE home_assistant_devices
        SET alias = ?, updated_at = ?
        WHERE entity_id = ?
        """,
        (alias.strip(), now, entity_id.strip()),
    )
    updated = cursor.rowcount > 0
    conn.commit()
    conn.close()
    if not updated:
        raise KeyError(f"Dispositivo nao encontrado: {entity_id}")
    return get_device(entity_id) or {}


def delete_device(entity_id: str) -> bool:
    init_devices_db()
    conn = _connect()
    cursor = conn.cursor()
    cursor.execute(
        "DELETE FROM home_assistant_devices WHERE entity_id = ?",
        (entity_id.strip(),),
    )
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def clear_devices() -> int:
    init_devices_db()
    conn = _connect()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM home_assistant_devices")
    deleted_count = cursor.rowcount
    conn.commit()
    conn.close()
    return deleted_count


def get_device(entity_id: str) -> dict[str, Any] | None:
    init_devices_db()
    conn = _connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT entity_id, domain, friendly_name, alias, state, attributes_json, last_seen_at, updated_at
        FROM home_assistant_devices
        WHERE entity_id = ?
        """,
        (entity_id.strip(),),
    )
    row = cursor.fetchone()
    conn.close()
    return _row_to_device(row) if row else None


def device_alias_map() -> dict[str, dict[str, str]]:
    devices = list_devices()
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


def resolve_device_reference(reference: str, domain: str | None = None) -> dict[str, Any] | None:
    clean_reference = (reference or "").strip()
    if not clean_reference:
        return None

    devices = list_devices(domain=domain)
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


def _row_to_device(row: sqlite3.Row) -> dict[str, Any]:
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
