"""
Memoria persistente do utilizador (SQLite).

Responsabilidade:
- Guardar factos simples (nome, preferencias, lembretes, etc.)
- Disponibilizar leitura e gestao desses factos

Nao contem logica de NLP.
"""

from db_utils import connect
from settings_store import SETTINGS_DEFAULTS, load_settings_values, update_settings


def _connect():
    return connect()


def _next_index(prefix):
    conn = _connect()
    c = conn.cursor()
    c.execute("SELECT key FROM user_memory WHERE key LIKE ?", (f"{prefix}%",))
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
    c.execute(
        """
        CREATE TABLE IF NOT EXISTS user_memory (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """
    )
    conn.commit()
    conn.close()


def save_fact(key, value):
    """
    Guarda ou atualiza um facto do utilizador.
    """
    conn = _connect()
    c = conn.cursor()
    c.execute(
        "INSERT OR REPLACE INTO user_memory (key, value) VALUES (?, ?)",
        (key, value),
    )
    conn.commit()
    conn.close()


def save_preference(preference_text):
    """
    Guarda uma preferencia do utilizador.
    """
    conn = _connect()
    c = conn.cursor()
    key = f"preference_{_next_index('preference_')}"
    c.execute(
        "INSERT INTO user_memory (key, value) VALUES (?, ?)",
        (key, preference_text),
    )
    conn.commit()
    conn.close()


def save_reminder(reminder_text):
    """
    Guarda um lembrete do utilizador.
    """
    conn = _connect()
    c = conn.cursor()
    key = f"reminder_{_next_index('reminder_')}"
    c.execute(
        "INSERT INTO user_memory (key, value) VALUES (?, ?)",
        (key, reminder_text),
    )
    conn.commit()
    conn.close()


def delete_fact(key):
    """
    Remove um facto da memoria.
    """
    conn = _connect()
    c = conn.cursor()
    c.execute("DELETE FROM user_memory WHERE key = ?", (key,))
    conn.commit()
    conn.close()


def delete_preference(index):
    """
    Remove uma preferencia pelo indice (1-based).
    """
    conn = _connect()
    c = conn.cursor()
    c.execute("SELECT key FROM user_memory WHERE key LIKE 'preference_%' ORDER BY key")
    keys = [row["key"] for row in c.fetchall()]
    if 1 <= index <= len(keys):
        key_to_delete = keys[index - 1]
        c.execute("DELETE FROM user_memory WHERE key = ?", (key_to_delete,))
        conn.commit()
    conn.close()


def delete_reminder(index):
    """
    Remove um lembrete pelo indice (1-based).
    """
    conn = _connect()
    c = conn.cursor()
    c.execute("SELECT key FROM user_memory WHERE key LIKE 'reminder_%' ORDER BY key")
    keys = [row["key"] for row in c.fetchall()]
    if 1 <= index <= len(keys):
        key_to_delete = keys[index - 1]
        c.execute("DELETE FROM user_memory WHERE key = ?", (key_to_delete,))
        conn.commit()
    conn.close()


def load_facts():
    """
    Devolve todos os factos conhecidos como dicionario.
    Inclui preferencias e lembretes como listas.
    """
    conn = _connect()
    c = conn.cursor()
    c.execute("SELECT key, value FROM user_memory")
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

    facts.update(load_settings_values())
    facts["preferences"] = preferences
    facts["reminders"] = reminders

    return facts


def list_memory_entries():
    """
    Devolve a memoria numa estrutura adequada para APIs e UI.
    """
    conn = _connect()
    c = conn.cursor()
    c.execute("SELECT key, value FROM user_memory")
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
        for key, value in load_settings_values().items()
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


def update_memory_entry(key, value):
    """
    Cria ou atualiza o valor de uma entrada de memoria.
    """
    clean_value = value.strip()

    if not clean_value:
        raise ValueError("O valor da memoria nao pode estar vazio.")

    if key in SETTINGS_DEFAULTS:
        update_settings({key: clean_value})
        return {
            "key": key,
            "value": clean_value,
            "type": "fact",
            "label": _memory_label_from_key(key),
            "index": None,
        }

    conn = _connect()
    c = conn.cursor()
    c.execute(
        "INSERT OR REPLACE INTO user_memory (key, value) VALUES (?, ?)",
        (key, clean_value),
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


def delete_memory_entry(key):
    """
    Remove uma entrada de memoria pelo identificador real.
    """
    if key in SETTINGS_DEFAULTS:
        default_value = SETTINGS_DEFAULTS.get(key, "")
        update_settings({key: default_value})
        return True

    conn = _connect()
    c = conn.cursor()
    c.execute("DELETE FROM user_memory WHERE key = ?", (key,))
    deleted = c.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def clear_memory():
    """
    Remove todas as entradas de memoria.
    """
    conn = _connect()
    c = conn.cursor()
    c.execute("DELETE FROM user_memory")
    deleted_count = c.rowcount
    conn.commit()
    conn.close()
    return deleted_count
