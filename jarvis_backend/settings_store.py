"""Persistencia explicita de configuracoes da aplicacao."""

from __future__ import annotations

from datetime import datetime, timezone

from db_utils import connect


SETTINGS_DEFAULTS = {
    "assistant_name": "Jarvis",
    "user_name": "",
    "wake_word_phrase": "Jarvis",
    "home_assistant_enabled": "false",
    "home_assistant_url": "",
    "home_assistant_token": "",
}

SETTINGS_LABELS = {
    "assistant_name": "Nome do Assistente",
    "user_name": "Nome do Utilizador",
    "wake_word_phrase": "Wake Word",
    "home_assistant_enabled": "Home Assistant Ativo",
    "home_assistant_url": "URL Home Assistant",
    "home_assistant_token": "Token Home Assistant",
}


def _normalize_setting_value(key: str, value: object) -> str:
    if key == "home_assistant_enabled":
        return "true" if str(value).strip().lower() in {"1", "true", "yes", "on"} else "false"
    return str(value or "").strip()


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def init_settings_db() -> None:
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    conn.commit()
    conn.close()


def list_settings() -> list[dict[str, str]]:
    init_settings_db()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute("SELECT key, value, updated_at FROM app_settings ORDER BY key")
    rows = cursor.fetchall()
    conn.close()

    saved = {
        row["key"]: {
            "key": row["key"],
            "value": row["value"],
            "label": SETTINGS_LABELS.get(row["key"], row["key"]),
            "updated_at": row["updated_at"],
        }
        for row in rows
    }

    entries = []
    for key, default_value in SETTINGS_DEFAULTS.items():
        if key == "home_assistant_enabled" and key not in saved:
            has_credentials = bool(
                str(saved.get("home_assistant_url", {}).get("value", "")).strip()
                and str(saved.get("home_assistant_token", {}).get("value", "")).strip()
            )
            default_value = "true" if has_credentials else default_value
        entries.append(
            saved.get(
                key,
                {
                    "key": key,
                    "value": default_value,
                    "label": SETTINGS_LABELS.get(key, key),
                    "updated_at": "",
                },
            )
        )
    return entries


def load_settings_values() -> dict[str, str]:
    values = {
        entry["key"]: entry["value"]
        for entry in list_settings()
    }

    assistant_name = values.get("assistant_name", "").strip() or SETTINGS_DEFAULTS["assistant_name"]
    values["assistant_name"] = assistant_name

    wake_word_phrase = values.get("wake_word_phrase", "").strip() or assistant_name
    values["wake_word_phrase"] = wake_word_phrase

    user_name = values.get("user_name", "").strip()
    values["user_name"] = user_name
    values["home_assistant_enabled"] = _normalize_setting_value(
        "home_assistant_enabled",
        values.get("home_assistant_enabled", SETTINGS_DEFAULTS["home_assistant_enabled"]),
    )
    values["name"] = user_name
    return values


def update_settings(values: dict[str, str]) -> list[dict[str, str]]:
    init_settings_db()
    now = _utc_now_iso()
    conn = connect()
    cursor = conn.cursor()

    for key, value in values.items():
        if key not in SETTINGS_DEFAULTS:
            continue
        clean_value = _normalize_setting_value(key, value)
        cursor.execute(
            """
            INSERT INTO app_settings (key, value, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET
                value=excluded.value,
                updated_at=excluded.updated_at
            """,
            (key, clean_value, now),
        )

    conn.commit()
    conn.close()
    return list_settings()


def clear_settings() -> int:
    init_settings_db()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM app_settings")
    deleted_count = cursor.rowcount
    conn.commit()
    conn.close()
    return deleted_count
