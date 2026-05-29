"""
Memoria persistente do utilizador (SQLite).

Responsabilidade:
- Guardar factos simples (nome, preferencias, lembretes, etc.)
- Disponibilizar leitura e gestao desses factos

Nao contem logica de NLP.
"""

from __future__ import annotations

from datetime import datetime, timezone

from db_utils import connect
from settings_store import (
    SETTINGS_DEFAULTS,
    _ensure_settings_schema,
    _normalize_setting_value,
    load_settings_values,
)


def _connect():
    return connect()


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _clean_user_id(user_id: str | None) -> str | None:
    return (user_id or "").strip() or None


def _user_filter_sql(user_id: str | None, *, column: str = "user_id") -> tuple[str, tuple[object, ...]]:
    clean_user_id = _clean_user_id(user_id)
    if clean_user_id is None:
        return f"{column} IS NULL", ()
    return f"{column} = ?", (clean_user_id,)


def _table_columns(cursor, table_name: str) -> set[str]:
    cursor.execute(f"PRAGMA table_info({table_name})")
    return {row["name"] for row in cursor.fetchall()}


def _table_exists(cursor, table_name: str) -> bool:
    cursor.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name = ?
        """,
        (table_name,),
    )
    return cursor.fetchone() is not None


def _ensure_facts_schema(cursor) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS user_facts (
            user_id TEXT,
            key TEXT NOT NULL,
            value TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (user_id, key)
        )
        """
    )


def _ensure_preferences_schema(cursor) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS user_preferences (
            user_id TEXT,
            sort_order INTEGER NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (user_id, sort_order)
        )
        """
    )


def _ensure_reminders_schema(cursor) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS user_reminders (
            user_id TEXT,
            sort_order INTEGER NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (user_id, sort_order)
        )
        """
    )


def _extract_sort_order(key: str, prefix: str) -> int | None:
    if not key.startswith(prefix):
        return None
    suffix = key.removeprefix(prefix)
    if suffix.isdigit():
        return int(suffix)
    return None


def _migrate_legacy_user_memory(cursor) -> None:
    if not _table_exists(cursor, "user_memory"):
        return

    columns = _table_columns(cursor, "user_memory")
    if {"key", "value"}.difference(columns):
        cursor.execute("DROP TABLE user_memory")
        return

    if "user_id" in columns:
        cursor.execute(
            """
            SELECT user_id, key, value
            FROM user_memory
            ORDER BY key
            """
        )
    else:
        cursor.execute(
            """
            SELECT NULL AS user_id, key, value
            FROM user_memory
            ORDER BY key
            """
        )

    rows = cursor.fetchall()
    if not rows:
        cursor.execute("DROP TABLE user_memory")
        return

    _ensure_settings_schema(cursor)
    now = _utc_now_iso()

    for row in rows:
        user_id = _clean_user_id(row["user_id"])
        key = str(row["key"] or "").strip()
        value = str(row["value"] or "")
        if not key:
            continue

        if key in SETTINGS_DEFAULTS:
            clean_value = _normalize_setting_value(key, value)
            cursor.execute(
                "DELETE FROM app_settings WHERE user_id IS ? AND key = ?",
                (user_id, key),
            )
            cursor.execute(
                """
                INSERT INTO app_settings (user_id, key, value, updated_at)
                VALUES (?, ?, ?, ?)
                """,
                (user_id, key, clean_value, now),
            )
            continue

        preference_order = _extract_sort_order(key, "preference_")
        if preference_order is not None:
            cursor.execute(
                """
                INSERT INTO user_preferences (user_id, sort_order, value, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(user_id, sort_order)
                DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                """,
                (user_id, preference_order, value, now),
            )
            continue

        reminder_order = _extract_sort_order(key, "reminder_")
        if reminder_order is not None:
            cursor.execute(
                """
                INSERT INTO user_reminders (user_id, sort_order, value, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(user_id, sort_order)
                DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
                """,
                (user_id, reminder_order, value, now),
            )
            continue

        cursor.execute(
            """
            INSERT INTO user_facts (user_id, key, value, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(user_id, key)
            DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """,
            (user_id, key, value, now),
        )

    cursor.execute("DROP TABLE user_memory")


def _memory_type_from_key(key):
    if key.startswith("preference_"):
        return "preference"
    if key.startswith("reminder_"):
        return "reminder"
    return "fact"


def _memory_index_from_key(key):
    for prefix in ("preference_", "reminder_"):
        suffix = key.removeprefix(prefix)
        if suffix != key and suffix.isdigit():
            return int(suffix)
    return None


def _sort_memory_keys(keys: list[str]) -> list[str]:
    return sorted(
        keys,
        key=lambda key: (
            _memory_index_from_key(key) is None,
            _memory_index_from_key(key) or 0,
            key.lower(),
        ),
    )


def _memory_label_from_key(key):
    if key == "name":
        return "Nome"
    if key == "assistant_name":
        return "Nome do Assistente"
    if key == "wake_word_phrase":
        return "Wake Word"
    if key == "wake_word_sensitivity":
        return "Sensibilidade Wake Word"
    if key == "llm_provider":
        return "Provedor LLM"
    if key == "ollama_url":
        return "URL Ollama"
    if key == "ollama_model":
        return "Modelo Ollama"
    if key == "openai_model":
        return "Modelo OpenAI"
    if key == "openai_api_key":
        return "Chave OpenAI"
    if key == "home_assistant_enabled":
        return "Home Assistant Ativo"
    if key == "home_assistant_url":
        return "URL Home Assistant"
    if key == "home_assistant_token":
        return "Token Home Assistant"

    entry_type = _memory_type_from_key(key)
    index = _memory_index_from_key(key)

    if entry_type == "preference":
        return f"Preferencia {index}" if index is not None else "Preferencia"

    if entry_type == "reminder":
        return f"Lembrete {index}" if index is not None else "Lembrete"

    return key.replace("_", " ").strip().title()


def _normalize_entry(key: str, value: str):
    return {
        "key": key,
        "value": value,
        "type": _memory_type_from_key(key),
        "label": _memory_label_from_key(key),
        "index": _memory_index_from_key(key),
    }


def _load_fact_rows(cursor, user_id: str | None):
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"""
        SELECT key, value
        FROM user_facts
        WHERE {where_sql}
        ORDER BY key
        """,
        params,
    )
    return cursor.fetchall()


def _load_ordered_value_rows(cursor, table_name: str, user_id: str | None):
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"""
        SELECT sort_order, value
        FROM {table_name}
        WHERE {where_sql}
        ORDER BY sort_order
        """,
        params,
    )
    return cursor.fetchall()


def _next_sort_order(cursor, table_name: str, user_id: str | None) -> int:
    where_sql, params = _user_filter_sql(user_id)
    cursor.execute(
        f"""
        SELECT COALESCE(MAX(sort_order), 0) + 1 AS next_sort_order
        FROM {table_name}
        WHERE {where_sql}
        """,
        params,
    )
    row = cursor.fetchone()
    return int(row["next_sort_order"] or 1)


def _upsert_fact(cursor, key: str, value: str, user_id: str | None = None) -> None:
    cursor.execute(
        """
        INSERT INTO user_facts (user_id, key, value, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(user_id, key)
        DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """,
        (_clean_user_id(user_id), key, value, _utc_now_iso()),
    )


def _upsert_ordered_value(
    cursor,
    table_name: str,
    sort_order: int,
    value: str,
    user_id: str | None = None,
) -> None:
    cursor.execute(
        f"""
        INSERT INTO {table_name} (user_id, sort_order, value, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(user_id, sort_order)
        DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
        """,
        (_clean_user_id(user_id), sort_order, value, _utc_now_iso()),
    )


def init_db():
    """
    Cria a base de dados se nao existir e migra a memoria legada.
    """
    conn = _connect()
    cursor = conn.cursor()
    _ensure_facts_schema(cursor)
    _ensure_preferences_schema(cursor)
    _ensure_reminders_schema(cursor)
    _migrate_legacy_user_memory(cursor)
    conn.commit()
    conn.close()


def save_fact(key, value, user_id: str | None = None):
    """
    Guarda ou atualiza um facto do utilizador.
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()
    _upsert_fact(cursor, key, value, user_id=user_id)
    conn.commit()
    conn.close()


def save_preference(preference_text, user_id: str | None = None):
    """
    Guarda uma preferencia do utilizador.
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()
    sort_order = _next_sort_order(cursor, "user_preferences", user_id)
    _upsert_ordered_value(
        cursor,
        "user_preferences",
        sort_order,
        preference_text,
        user_id=user_id,
    )
    conn.commit()
    conn.close()


def save_reminder(reminder_text, user_id: str | None = None):
    """
    Guarda um lembrete do utilizador.
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()
    sort_order = _next_sort_order(cursor, "user_reminders", user_id)
    _upsert_ordered_value(
        cursor,
        "user_reminders",
        sort_order,
        reminder_text,
        user_id=user_id,
    )
    conn.commit()
    conn.close()


def delete_fact(key, user_id: str | None = None):
    """
    Remove um facto da memoria.
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()
    cursor.execute(
        "DELETE FROM user_facts WHERE user_id IS ? AND key = ?",
        (_clean_user_id(user_id), key),
    )
    conn.commit()
    conn.close()


def delete_preference(index, user_id: str | None = None):
    """
    Remove uma preferencia pelo indice (1-based).
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()
    rows = _load_ordered_value_rows(cursor, "user_preferences", user_id)
    if 1 <= index <= len(rows):
        sort_order = int(rows[index - 1]["sort_order"])
        cursor.execute(
            "DELETE FROM user_preferences WHERE user_id IS ? AND sort_order = ?",
            (_clean_user_id(user_id), sort_order),
        )
        conn.commit()
    conn.close()


def delete_reminder(index, user_id: str | None = None):
    """
    Remove um lembrete pelo indice (1-based).
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()
    rows = _load_ordered_value_rows(cursor, "user_reminders", user_id)
    if 1 <= index <= len(rows):
        sort_order = int(rows[index - 1]["sort_order"])
        cursor.execute(
            "DELETE FROM user_reminders WHERE user_id IS ? AND sort_order = ?",
            (_clean_user_id(user_id), sort_order),
        )
        conn.commit()
    conn.close()


def load_facts(user_id: str | None = None):
    """
    Devolve todos os factos conhecidos como dicionario.
    Inclui preferencias e lembretes como listas.
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()

    facts = {
        row["key"]: row["value"]
        for row in _load_fact_rows(cursor, user_id)
    }
    preferences = [row["value"] for row in _load_ordered_value_rows(cursor, "user_preferences", user_id)]
    reminders = [row["value"] for row in _load_ordered_value_rows(cursor, "user_reminders", user_id)]
    conn.close()

    for key, value in load_settings_values(user_id=user_id).items():
        facts.setdefault(key, value)
    facts["preferences"] = preferences
    facts["reminders"] = reminders

    return facts


def list_memory_entries(user_id: str | None = None):
    """
    Devolve a memoria numa estrutura adequada para APIs e UI.
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()

    entries = [
        _normalize_entry(row["key"], row["value"])
        for row in _load_fact_rows(cursor, user_id)
    ]

    for row in _load_ordered_value_rows(cursor, "user_preferences", user_id):
        sort_order = int(row["sort_order"])
        entries.append(
            _normalize_entry(f"preference_{sort_order}", row["value"])
        )

    for row in _load_ordered_value_rows(cursor, "user_reminders", user_id):
        sort_order = int(row["sort_order"])
        entries.append(
            _normalize_entry(f"reminder_{sort_order}", row["value"])
        )

    conn.close()

    type_order = {
        "fact": 0,
        "preference": 1,
        "reminder": 2,
    }

    entries.sort(
        key=lambda entry: (
            type_order.get(entry["type"], 99),
            entry["index"] if entry["index"] is not None else 0,
            entry["label"].lower(),
            entry["key"].lower(),
        )
    )

    return entries


def update_memory_entry(key, value, user_id: str | None = None):
    """
    Cria ou atualiza o valor de uma entrada de memoria.
    """
    clean_value = value.strip()

    if not clean_value:
        raise ValueError("O valor da memoria nao pode estar vazio.")

    if key in SETTINGS_DEFAULTS:
        raise ValueError("As configuracoes da conta devem ser alteradas pelo endpoint /settings.")

    init_db()
    conn = _connect()
    cursor = conn.cursor()

    preference_order = _extract_sort_order(key, "preference_")
    if preference_order is not None:
        _upsert_ordered_value(
            cursor,
            "user_preferences",
            preference_order,
            clean_value,
            user_id=user_id,
        )
        conn.commit()
        conn.close()
        return {
            "key": key,
            "value": clean_value,
            "type": "preference",
            "label": _memory_label_from_key(key),
            "index": preference_order,
        }

    reminder_order = _extract_sort_order(key, "reminder_")
    if reminder_order is not None:
        _upsert_ordered_value(
            cursor,
            "user_reminders",
            reminder_order,
            clean_value,
            user_id=user_id,
        )
        conn.commit()
        conn.close()
        return {
            "key": key,
            "value": clean_value,
            "type": "reminder",
            "label": _memory_label_from_key(key),
            "index": reminder_order,
        }

    _upsert_fact(cursor, key, clean_value, user_id=user_id)
    conn.commit()
    conn.close()

    return {
        "key": key,
        "value": clean_value,
        "type": "fact",
        "label": _memory_label_from_key(key),
        "index": None,
    }


def delete_memory_entry(key, user_id: str | None = None):
    """
    Remove uma entrada de memoria pelo identificador real.
    """
    if key in SETTINGS_DEFAULTS:
        raise ValueError("As configuracoes da conta devem ser removidas pelo endpoint /settings.")

    init_db()
    conn = _connect()
    cursor = conn.cursor()

    preference_order = _extract_sort_order(key, "preference_")
    if preference_order is not None:
        cursor.execute(
            "DELETE FROM user_preferences WHERE user_id IS ? AND sort_order = ?",
            (_clean_user_id(user_id), preference_order),
        )
        deleted = cursor.rowcount > 0
        conn.commit()
        conn.close()
        return deleted

    reminder_order = _extract_sort_order(key, "reminder_")
    if reminder_order is not None:
        cursor.execute(
            "DELETE FROM user_reminders WHERE user_id IS ? AND sort_order = ?",
            (_clean_user_id(user_id), reminder_order),
        )
        deleted = cursor.rowcount > 0
        conn.commit()
        conn.close()
        return deleted

    cursor.execute(
        "DELETE FROM user_facts WHERE user_id IS ? AND key = ?",
        (_clean_user_id(user_id), key),
    )
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def clear_memory(user_id: str | None = None):
    """
    Remove todas as entradas semanticas de memoria.
    Nao limpa configuracoes da conta.
    """
    init_db()
    conn = _connect()
    cursor = conn.cursor()
    deleted_count = 0

    for table_name in ("user_facts", "user_preferences", "user_reminders"):
        where_sql, params = _user_filter_sql(user_id)
        cursor.execute(f"DELETE FROM {table_name} WHERE {where_sql}", params)
        deleted_count += cursor.rowcount

    conn.commit()
    conn.close()
    return deleted_count
