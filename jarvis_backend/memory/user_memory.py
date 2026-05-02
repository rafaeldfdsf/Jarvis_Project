"""
Memoria persistente do utilizador (SQLite).

Responsabilidade:
- Guardar factos simples (nome, preferencias, lembretes, etc.)
- Disponibilizar leitura e gestao desses factos

Nao contem logica de NLP.
"""

from __future__ import annotations

from db_utils import connect
from settings_store import SETTINGS_DEFAULTS, load_settings_values, update_settings


def _connect():
    return connect()


def _user_filter_sql(user_id: str | None) -> tuple[str, tuple[object, ...]]:
    if user_id is None:
        return "user_id IS NULL", ()
    return "user_id = ?", ((user_id or "").strip(),)


def _table_columns(cursor, table_name: str) -> set[str]:
    cursor.execute(f"PRAGMA table_info({table_name})")
    return {row["name"] for row in cursor.fetchall()}


def _ensure_memory_schema(cursor) -> None:
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS user_memory (
            user_id TEXT,
            key TEXT NOT NULL,
            value TEXT,
            PRIMARY KEY (user_id, key)
        )
        """
    )

    columns = _table_columns(cursor, "user_memory")
    if "user_id" in columns:
        return

    cursor.execute("ALTER TABLE user_memory RENAME TO user_memory_legacy")
    cursor.execute(
        """
        CREATE TABLE user_memory (
            user_id TEXT,
            key TEXT NOT NULL,
            value TEXT,
            PRIMARY KEY (user_id, key)
        )
        """
    )
    cursor.execute(
        """
        INSERT INTO user_memory (user_id, key, value)
        SELECT NULL, key, value
        FROM user_memory_legacy
        """
    )
    cursor.execute("DROP TABLE user_memory_legacy")


def _next_index(prefix, user_id: str | None = None):
    conn = _connect()
    c = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    c.execute(
        f"SELECT key FROM user_memory WHERE {where_sql} AND key LIKE ?",
        (*params, f"{prefix}%"),
    )
    keys = [row["key"] for row in c.fetchall()]
    conn.close()

    max_index = 0

    for key in keys:
        suffix = key.removeprefix(prefix)
        if suffix.isdigit():
            max_index = max(max_index, int(suffix))

    return max_index + 1


def _memory_type_from_key(key):
    if key.startswith("preference_"):
        return "preference"
    if key.startswith("reminder_"):
        return "reminder"
    return "fact"


def _memory_index_from_key(key):
    for prefix in ("preference_", "reminder_"):
        if key.startswith(prefix):
            suffix = key.removeprefix(prefix)
            if suffix.isdigit():
                return int(suffix)
    return None


def _memory_label_from_key(key):
    if key == "name":
        return "Nome"
    if key == "assistant_name":
        return "Nome do Assistente"
    if key == "wake_word_phrase":
        return "Wake Word"
    if key == "wake_word_sensitivity":
        return "Sensibilidade Wake Word"
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


def _normalize_entry(row):
    key = row["key"]

    return {
        "key": key,
        "value": row["value"],
        "type": _memory_type_from_key(key),
        "label": _memory_label_from_key(key),
        "index": _memory_index_from_key(key),
    }


def init_db():
    """
    Cria a base de dados se nao existir.
    """
    conn = _connect()
    c = conn.cursor()
    _ensure_memory_schema(c)
    conn.commit()
    conn.close()


def save_fact(key, value, user_id: str | None = None):
    """
    Guarda ou atualiza um facto do utilizador.
    """
    init_db()
    conn = _connect()
    c = conn.cursor()
    c.execute(
        "DELETE FROM user_memory WHERE user_id IS ? AND key = ?",
        (((user_id or "").strip() or None), key),
    )
    c.execute(
        "INSERT INTO user_memory (user_id, key, value) VALUES (?, ?, ?)",
        (((user_id or "").strip() or None), key, value),
    )
    conn.commit()
    conn.close()


def save_preference(preference_text, user_id: str | None = None):
    """
    Guarda uma preferencia do utilizador.
    """
    init_db()
    conn = _connect()
    c = conn.cursor()
    key = f"preference_{_next_index('preference_', user_id=user_id)}"
    c.execute(
        "INSERT INTO user_memory (user_id, key, value) VALUES (?, ?, ?)",
        (((user_id or "").strip() or None), key, preference_text),
    )
    conn.commit()
    conn.close()


def save_reminder(reminder_text, user_id: str | None = None):
    """
    Guarda um lembrete do utilizador.
    """
    init_db()
    conn = _connect()
    c = conn.cursor()
    key = f"reminder_{_next_index('reminder_', user_id=user_id)}"
    c.execute(
        "INSERT INTO user_memory (user_id, key, value) VALUES (?, ?, ?)",
        (((user_id or "").strip() or None), key, reminder_text),
    )
    conn.commit()
    conn.close()


def delete_fact(key, user_id: str | None = None):
    """
    Remove um facto da memoria.
    """
    init_db()
    conn = _connect()
    c = conn.cursor()
    c.execute(
        "DELETE FROM user_memory WHERE user_id IS ? AND key = ?",
        (((user_id or "").strip() or None), key),
    )
    conn.commit()
    conn.close()


def delete_preference(index, user_id: str | None = None):
    """
    Remove uma preferencia pelo indice (1-based).
    """
    init_db()
    conn = _connect()
    c = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    c.execute(
        f"SELECT key FROM user_memory WHERE {where_sql} AND key LIKE 'preference_%' ORDER BY key",
        params,
    )
    keys = [row["key"] for row in c.fetchall()]
    if 1 <= index <= len(keys):
        key_to_delete = keys[index - 1]
        c.execute(
            f"DELETE FROM user_memory WHERE {where_sql} AND key = ?",
            (*params, key_to_delete),
        )
        conn.commit()
    conn.close()


def delete_reminder(index, user_id: str | None = None):
    """
    Remove um lembrete pelo indice (1-based).
    """
    init_db()
    conn = _connect()
    c = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    c.execute(
        f"SELECT key FROM user_memory WHERE {where_sql} AND key LIKE 'reminder_%' ORDER BY key",
        params,
    )
    keys = [row["key"] for row in c.fetchall()]
    if 1 <= index <= len(keys):
        key_to_delete = keys[index - 1]
        c.execute(
            f"DELETE FROM user_memory WHERE {where_sql} AND key = ?",
            (*params, key_to_delete),
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
    c = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    c.execute(f"SELECT key, value FROM user_memory WHERE {where_sql}", params)
    rows = c.fetchall()
    conn.close()

    facts = {}
    preferences = []
    reminders = []

    for key, value in [(row["key"], row["value"]) for row in rows]:
        if key.startswith("preference_"):
            preferences.append(value)
        elif key.startswith("reminder_"):
            reminders.append(value)
        else:
            facts[key] = value

    facts.update(load_settings_values(user_id=user_id))
    facts["preferences"] = preferences
    facts["reminders"] = reminders

    return facts


def list_memory_entries(user_id: str | None = None):
    """
    Devolve a memoria numa estrutura adequada para APIs e UI.
    """
    init_db()
    conn = _connect()
    c = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    c.execute(f"SELECT key, value FROM user_memory WHERE {where_sql}", params)
    rows = c.fetchall()
    conn.close()

    entries = [
        _normalize_entry(row)
        for row in rows
        if row["key"] not in SETTINGS_DEFAULTS
    ]

    settings_entries = [
        {
            "key": key,
            "value": value,
            "type": "fact",
            "label": _memory_label_from_key(key),
            "index": None,
        }
        for key, value in load_settings_values(user_id=user_id).items()
        if key in SETTINGS_DEFAULTS
    ]
    entries.extend(settings_entries)

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
        update_settings({key: clean_value}, user_id=user_id)
        return {
            "key": key,
            "value": clean_value,
            "type": "fact",
            "label": _memory_label_from_key(key),
            "index": None,
        }

    init_db()
    conn = _connect()
    c = conn.cursor()
    c.execute(
        "DELETE FROM user_memory WHERE user_id IS ? AND key = ?",
        (((user_id or "").strip() or None), key),
    )
    c.execute(
        "INSERT INTO user_memory (user_id, key, value) VALUES (?, ?, ?)",
        (((user_id or "").strip() or None), key, clean_value),
    )
    conn.commit()
    conn.close()

    return {
        "key": key,
        "value": clean_value,
        "type": _memory_type_from_key(key),
        "label": _memory_label_from_key(key),
        "index": _memory_index_from_key(key),
    }


def delete_memory_entry(key, user_id: str | None = None):
    """
    Remove uma entrada de memoria pelo identificador real.
    """
    if key in SETTINGS_DEFAULTS:
        default_value = SETTINGS_DEFAULTS.get(key, "")
        update_settings({key: default_value}, user_id=user_id)
        return True

    init_db()
    conn = _connect()
    c = conn.cursor()
    c.execute(
        "DELETE FROM user_memory WHERE user_id IS ? AND key = ?",
        (((user_id or "").strip() or None), key),
    )
    deleted = c.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def clear_memory(user_id: str | None = None):
    """
    Remove todas as entradas de memoria.
    """
    init_db()
    conn = _connect()
    c = conn.cursor()
    where_sql, params = _user_filter_sql(user_id)
    c.execute(f"DELETE FROM user_memory WHERE {where_sql}", params)
    deleted_count = c.rowcount
    conn.commit()
    conn.close()
    return deleted_count
