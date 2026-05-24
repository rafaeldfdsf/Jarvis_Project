"""Persistencia explicita de configuracoes da aplicacao."""

from __future__ import annotations

from datetime import datetime, timezone

from config import OPENAI_CHAT_MODEL, OLLAMA_URL, MODEL
from db_utils import connect


SETTINGS_DEFAULTS = {
    "assistant_name": "Jarvis",
    "user_name": "",
    "wake_word_phrase": "Jarvis",
    "wake_word_sensitivity": "40",
    "llm_provider": "ollama",
    "ollama_url": OLLAMA_URL,
    "ollama_model": MODEL,
    "openai_model": OPENAI_CHAT_MODEL,
    "openai_api_key": "",
    "home_assistant_enabled": "false",
    "home_assistant_url": "",
    "home_assistant_token": "",
}

SETTINGS_LABELS = {
    "assistant_name": "Nome do Assistente",
    "user_name": "Nome do Utilizador",
    "wake_word_phrase": "Wake Word",
    "wake_word_sensitivity": "Sensibilidade Wake Word",
    "llm_provider": "Provedor LLM",
    "ollama_url": "URL Ollama",
    "ollama_model": "Modelo Ollama",
    "openai_model": "Modelo OpenAI",
    "openai_api_key": "Chave OpenAI",
    "home_assistant_enabled": "Home Assistant Ativo",
    "home_assistant_url": "URL Home Assistant",
    "home_assistant_token": "Token Home Assistant",
}


def _normalize_setting_value(key: str, value: object) -> str:
    if key == "home_assistant_enabled":
        return "true" if str(value).strip().lower() in {"1", "true", "yes", "on"} else "false"
    if key == "llm_provider":
        return "openai" if str(value).strip().lower() == "openai" else "ollama"
    if key == "wake_word_sensitivity":
        try:
            level = int(str(value).strip() or SETTINGS_DEFAULTS[key])
        except ValueError:
            level = int(SETTINGS_DEFAULTS[key])
        level = max(0, min(100, level))
        return str(level)
    return str(value or "").strip()


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _table_columns(cursor, table_name: str) -> set[str]:
    cursor.execute(f"PRAGMA table_info({table_name})")
    return {row["name"] for row in cursor.fetchall()}


def _ensure_settings_schema(cursor) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS app_settings (
            user_id TEXT,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )

    columns = _table_columns(cursor, "app_settings")
    if "user_id" in columns:
        cursor.execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_app_settings_user_key
            ON app_settings (user_id, key)
            """
        )
        return

    cursor.execute("ALTER TABLE app_settings RENAME TO app_settings_legacy")
    cursor.execute(
        """
        CREATE TABLE app_settings (
            user_id TEXT,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    cursor.execute(
        """
        INSERT INTO app_settings (user_id, key, value, updated_at)
        SELECT NULL, key, value, updated_at
        FROM app_settings_legacy
        """
    )
    cursor.execute("DROP TABLE app_settings_legacy")
    cursor.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_app_settings_user_key
        ON app_settings (user_id, key)
        """
    )


def _user_filter_sql(user_id: str | None) -> tuple[str, tuple[object, ...]]:
    if user_id is None:
        return "user_id IS NULL", ()
    return "user_id = ?", ((user_id or "").strip(),)


def init_settings_db() -> None:
    conn = connect()
    cursor = conn.cursor()
    _ensure_settings_schema(cursor)
    conn.commit()
    conn.close()


def list_settings(user_id: str | None = None) -> list[dict[str, str]]:
    init_settings_db()
    conn = connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"SELECT key, value, updated_at FROM app_settings WHERE {where_sql} ORDER BY key",
        params,
    )
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


def load_settings_values(user_id: str | None = None) -> dict[str, str]:
    values = {
        entry["key"]: entry["value"]
        for entry in list_settings(user_id=user_id)
    }

    assistant_name = values.get("assistant_name", "").strip() or SETTINGS_DEFAULTS["assistant_name"]
    values["assistant_name"] = assistant_name

    wake_word_phrase = values.get("wake_word_phrase", "").strip() or assistant_name
    values["wake_word_phrase"] = wake_word_phrase
    values["wake_word_sensitivity"] = _normalize_setting_value(
        "wake_word_sensitivity",
        values.get("wake_word_sensitivity", SETTINGS_DEFAULTS["wake_word_sensitivity"]),
    )

    user_name = values.get("user_name", "").strip()
    values["user_name"] = user_name
    values["home_assistant_enabled"] = _normalize_setting_value(
        "home_assistant_enabled",
        values.get("home_assistant_enabled", SETTINGS_DEFAULTS["home_assistant_enabled"]),
    )
    values["llm_provider"] = _normalize_setting_value(
        "llm_provider",
        values.get("llm_provider", SETTINGS_DEFAULTS["llm_provider"]),
    )
    values["ollama_url"] = values.get("ollama_url", "").strip() or SETTINGS_DEFAULTS["ollama_url"]
    values["ollama_model"] = values.get("ollama_model", "").strip() or SETTINGS_DEFAULTS["ollama_model"]
    values["openai_model"] = values.get("openai_model", "").strip() or SETTINGS_DEFAULTS["openai_model"]
    values["openai_api_key"] = values.get("openai_api_key", "").strip()
    values["name"] = user_name
    return values


def update_settings(values: dict[str, str], user_id: str | None = None) -> list[dict[str, str]]:
    init_settings_db()
    now = _utc_now_iso()
    clean_user_id = (user_id or "").strip() or None
    conn = connect()
    cursor = conn.cursor()

    for key, value in values.items():
        if key not in SETTINGS_DEFAULTS:
            continue
        clean_value = _normalize_setting_value(key, value)
        cursor.execute(
            "DELETE FROM app_settings WHERE user_id IS ? AND key = ?",
            (clean_user_id, key),
        )
        cursor.execute(
            """
            INSERT INTO app_settings (user_id, key, value, updated_at)
            VALUES (?, ?, ?, ?)
            """,
            (clean_user_id, key, clean_value, now),
        )

    conn.commit()
    conn.close()
    return list_settings(user_id=user_id)


def clear_settings(user_id: str | None = None) -> int:
    init_settings_db()
    conn = connect()
    cursor = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(f"DELETE FROM app_settings WHERE {where_sql}", params)
    deleted_count = cursor.rowcount
    conn.commit()
    conn.close()
    return deleted_count
