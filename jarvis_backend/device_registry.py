"""Registo central de dispositivos e capacidades."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from db_utils import connect


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def init_device_registry() -> None:
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS devices (
            device_id TEXT PRIMARY KEY,
            owner_user_id TEXT,
            name TEXT NOT NULL,
            device_type TEXT NOT NULL,
            platform TEXT NOT NULL DEFAULT '',
            location TEXT NOT NULL DEFAULT '',
            is_active INTEGER NOT NULL DEFAULT 1,
            preferred_for_wake_word INTEGER NOT NULL DEFAULT 0,
            preferred_for_tts INTEGER NOT NULL DEFAULT 0,
            preferred_for_desktop_control INTEGER NOT NULL DEFAULT 0,
            connected INTEGER NOT NULL DEFAULT 0,
            last_seen_at TEXT NOT NULL DEFAULT '',
            last_error TEXT NOT NULL DEFAULT '',
            metadata_json TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS device_capabilities (
            device_id TEXT NOT NULL,
            capability TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (device_id, capability)
        )
        """
    )
    cursor.execute("PRAGMA table_info(devices)")
    columns = {row["name"] for row in cursor.fetchall()}
    if "owner_user_id" not in columns:
        cursor.execute("ALTER TABLE devices ADD COLUMN owner_user_id TEXT")
    conn.commit()
    conn.close()


def _decode_metadata(raw_value: str) -> dict[str, Any]:
    try:
        data = json.loads(raw_value or "{}")
        if isinstance(data, dict):
            return data
    except json.JSONDecodeError:
        return {}
    return {}


def _list_capabilities(cursor, device_id: str) -> list[str]:
    cursor.execute(
        """
        SELECT capability
        FROM device_capabilities
        WHERE device_id = ?
        ORDER BY capability
        """,
        (device_id,),
    )
    return [row["capability"] for row in cursor.fetchall()]


def _normalize_device_row(row, cursor) -> dict[str, Any]:
    return {
        "device_id": row["device_id"],
        "owner_user_id": row["owner_user_id"] or "",
        "name": row["name"],
        "device_type": row["device_type"],
        "platform": row["platform"],
        "location": row["location"],
        "is_active": bool(row["is_active"]),
        "preferred_for_wake_word": bool(row["preferred_for_wake_word"]),
        "preferred_for_tts": bool(row["preferred_for_tts"]),
        "preferred_for_desktop_control": bool(row["preferred_for_desktop_control"]),
        "connected": bool(row["connected"]),
        "last_seen_at": row["last_seen_at"],
        "last_error": row["last_error"],
        "metadata": _decode_metadata(row["metadata_json"]),
        "capabilities": _list_capabilities(cursor, row["device_id"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def upsert_device(
    *,
    device_id: str,
    name: str | None = None,
    device_type: str | None = None,
    platform: str | None = None,
    location: str | None = None,
    metadata: dict[str, Any] | None = None,
    capabilities: list[str] | None = None,
    connected: bool | None = None,
    owner_user_id: str | None = None,
) -> dict[str, Any]:
    init_device_registry()
    clean_device_id = (device_id or "").strip()
    if not clean_device_id:
        raise ValueError("device_id obrigatorio.")

    now = _utc_now_iso()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM devices WHERE device_id = ?", (clean_device_id,))
    existing = cursor.fetchone()

    if existing is None:
        cursor.execute(
            """
            INSERT INTO devices (
                device_id,
                owner_user_id,
                name,
                device_type,
                platform,
                location,
                connected,
                last_seen_at,
                last_error,
                metadata_json,
                created_at,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                clean_device_id,
                (owner_user_id or "").strip() or None,
                (name or clean_device_id).strip() or clean_device_id,
                (device_type or "unknown").strip() or "unknown",
                (platform or "").strip(),
                (location or "").strip(),
                1 if connected is not False else 0,
                now,
                "",
                json.dumps(metadata or {}, ensure_ascii=True, sort_keys=True),
                now,
                now,
            ),
        )
    else:
        merged_metadata = _decode_metadata(existing["metadata_json"])
        if metadata:
            merged_metadata.update(metadata)

        cursor.execute(
            """
            UPDATE devices
            SET owner_user_id = ?,
                name = ?,
                device_type = ?,
                platform = ?,
                location = ?,
                connected = ?,
                last_seen_at = ?,
                metadata_json = ?,
                updated_at = ?
            WHERE device_id = ?
            """,
            (
                (owner_user_id or existing["owner_user_id"] or "").strip() or None,
                (name or existing["name"]).strip() or clean_device_id,
                (device_type or existing["device_type"]).strip() or "unknown",
                (platform if platform is not None else existing["platform"]).strip(),
                (location if location is not None else existing["location"]).strip(),
                int(existing["connected"] if connected is None else bool(connected)),
                now,
                json.dumps(merged_metadata, ensure_ascii=True, sort_keys=True),
                now,
                clean_device_id,
            ),
        )

    if capabilities is not None:
        clean_capabilities = sorted({capability.strip() for capability in capabilities if capability and capability.strip()})
        cursor.execute("DELETE FROM device_capabilities WHERE device_id = ?", (clean_device_id,))
        for capability in clean_capabilities:
            cursor.execute(
                """
                INSERT INTO device_capabilities (device_id, capability, updated_at)
                VALUES (?, ?, ?)
                """,
                (clean_device_id, capability, now),
            )

    conn.commit()
    cursor.execute("SELECT * FROM devices WHERE device_id = ?", (clean_device_id,))
    row = cursor.fetchone()
    payload = _normalize_device_row(row, cursor)
    conn.close()
    return payload


def set_device_connection_state(
    device_id: str,
    *,
    connected: bool,
    last_error: str = "",
) -> None:
    init_device_registry()
    now = _utc_now_iso()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        UPDATE devices
        SET connected = ?,
            last_seen_at = ?,
            last_error = ?,
            updated_at = ?
        WHERE device_id = ?
        """,
        (1 if connected else 0, now, last_error.strip(), now, device_id),
    )
    conn.commit()
    conn.close()


def touch_device(device_id: str) -> None:
    init_device_registry()
    now = _utc_now_iso()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        UPDATE devices
        SET last_seen_at = ?,
            updated_at = ?
        WHERE device_id = ?
        """,
        (now, now, device_id),
    )
    conn.commit()
    conn.close()


def list_registered_devices(user_id: str | None = None) -> list[dict[str, Any]]:
    init_device_registry()
    conn = connect()
    cursor = conn.cursor()
    if user_id is None:
        cursor.execute(
            """
            SELECT *
            FROM devices
            WHERE owner_user_id IS NULL
            ORDER BY
                preferred_for_desktop_control DESC,
                preferred_for_wake_word DESC,
                preferred_for_tts DESC,
                connected DESC,
                name COLLATE NOCASE ASC
            """
        )
    else:
        cursor.execute(
            """
            SELECT *
            FROM devices
            WHERE owner_user_id = ? OR owner_user_id IS NULL
            ORDER BY
                preferred_for_desktop_control DESC,
                preferred_for_wake_word DESC,
                preferred_for_tts DESC,
                connected DESC,
                name COLLATE NOCASE ASC
            """,
            ((user_id or "").strip(),),
        )
    rows = cursor.fetchall()
    devices = [_normalize_device_row(row, cursor) for row in rows]
    conn.close()
    return devices


def get_device(device_id: str, user_id: str | None = None) -> dict[str, Any] | None:
    init_device_registry()
    conn = connect()
    cursor = conn.cursor()
    if user_id is None:
        cursor.execute(
            "SELECT * FROM devices WHERE device_id = ? AND owner_user_id IS NULL",
            (device_id,),
        )
    else:
        cursor.execute(
            "SELECT * FROM devices WHERE device_id = ? AND (owner_user_id = ? OR owner_user_id IS NULL)",
            (device_id, (user_id or "").strip()),
        )
    row = cursor.fetchone()
    if row is None:
        conn.close()
        return None

    payload = _normalize_device_row(row, cursor)
    conn.close()
    return payload


def update_device(device_id: str, updates: dict[str, Any], user_id: str | None = None) -> dict[str, Any]:
    init_device_registry()
    existing = get_device(device_id, user_id=user_id)
    if existing is None:
        raise KeyError(f"Dispositivo nao encontrado: {device_id}")

    allowed_fields = {
        "name",
        "location",
        "platform",
        "is_active",
        "preferred_for_wake_word",
        "preferred_for_tts",
        "preferred_for_desktop_control",
    }
    clean_updates = {
        key: value
        for key, value in updates.items()
        if key in allowed_fields
    }

    now = _utc_now_iso()
    conn = connect()
    cursor = conn.cursor()

    unique_preference_fields = (
        "preferred_for_wake_word",
        "preferred_for_tts",
        "preferred_for_desktop_control",
    )
    for field in unique_preference_fields:
        if clean_updates.get(field) is True:
            if user_id is None:
                cursor.execute(
                    f"UPDATE devices SET {field} = 0, updated_at = ? WHERE device_id <> ? AND owner_user_id IS NULL",
                    (now, device_id),
                )
            else:
                cursor.execute(
                    f"""
                    UPDATE devices
                    SET {field} = 0, updated_at = ?
                    WHERE device_id <> ? AND (owner_user_id = ? OR owner_user_id IS NULL)
                    """,
                    (now, device_id, (user_id or "").strip()),
                )

    cursor.execute(
        """
        UPDATE devices
        SET owner_user_id = ?,
            name = ?,
            location = ?,
            platform = ?,
            is_active = ?,
            preferred_for_wake_word = ?,
            preferred_for_tts = ?,
            preferred_for_desktop_control = ?,
            updated_at = ?
        WHERE device_id = ?
        """,
        (
            (user_id or existing["owner_user_id"] or "").strip() or None,
            str(clean_updates.get("name", existing["name"])).strip() or existing["device_id"],
            str(clean_updates.get("location", existing["location"])).strip(),
            str(clean_updates.get("platform", existing["platform"])).strip(),
            1 if bool(clean_updates.get("is_active", existing["is_active"])) else 0,
            1 if bool(clean_updates.get("preferred_for_wake_word", existing["preferred_for_wake_word"])) else 0,
            1 if bool(clean_updates.get("preferred_for_tts", existing["preferred_for_tts"])) else 0,
            1 if bool(clean_updates.get("preferred_for_desktop_control", existing["preferred_for_desktop_control"])) else 0,
            now,
            device_id,
        ),
    )
    conn.commit()
    cursor.execute("SELECT * FROM devices WHERE device_id = ?", (device_id,))
    row = cursor.fetchone()
    payload = _normalize_device_row(row, cursor)
    conn.close()
    return payload
