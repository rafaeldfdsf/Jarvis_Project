import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from memory.extract import extract_user_facts
from memory.user_memory import (
    clear_memory,
    delete_memory_entry,
    delete_preference,
    delete_reminder,
    init_db,
    list_memory_entries,
    load_facts,
    update_memory_entry,
)
from settings_store import update_settings


class MemoryFeatureTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "memory-tests.db"
        self.memory_connect_patcher = patch(
            "memory.user_memory._connect",
            side_effect=self._connect_to_temp_db,
        )
        self.settings_connect_patcher = patch(
            "settings_store.connect",
            side_effect=self._connect_to_temp_db,
        )
        self.memory_connect_patcher.start()
        self.settings_connect_patcher.start()
        init_db()

    def tearDown(self):
        self.memory_connect_patcher.stop()
        self.settings_connect_patcher.stop()
        self.temp_dir.cleanup()

    def _connect_to_temp_db(self):
        conn = sqlite3.connect(self.db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn

    def _insert_fact(self, key: str, value: str, user_id: str | None = None):
        conn = self._connect_to_temp_db()
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO user_facts (user_id, key, value, updated_at)
            VALUES (?, ?, ?, '2026-05-24T00:00:00+00:00')
            """,
            (((user_id or "").strip() or None), key, value),
        )
        conn.commit()
        conn.close()

    def _insert_preference(self, sort_order: int, value: str, user_id: str | None = None):
        conn = self._connect_to_temp_db()
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO user_preferences (user_id, sort_order, value, updated_at)
            VALUES (?, ?, ?, '2026-05-24T00:00:00+00:00')
            """,
            (((user_id or "").strip() or None), sort_order, value),
        )
        conn.commit()
        conn.close()

    def _insert_reminder(self, sort_order: int, value: str, user_id: str | None = None):
        conn = self._connect_to_temp_db()
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO user_reminders (user_id, sort_order, value, updated_at)
            VALUES (?, ?, ?, '2026-05-24T00:00:00+00:00')
            """,
            (((user_id or "").strip() or None), sort_order, value),
        )
        conn.commit()
        conn.close()

    def _create_legacy_user_memory(self):
        conn = self._connect_to_temp_db()
        cursor = conn.cursor()
        cursor.execute("DROP TABLE IF EXISTS user_facts")
        cursor.execute("DROP TABLE IF EXISTS user_preferences")
        cursor.execute("DROP TABLE IF EXISTS user_reminders")
        cursor.execute("DROP TABLE IF EXISTS user_memory")
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
        conn.commit()
        conn.close()

    def _insert_legacy_memory_entry(self, key: str, value: str, user_id: str | None = None):
        conn = self._connect_to_temp_db()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO user_memory (user_id, key, value) VALUES (?, ?, ?)",
            (((user_id or "").strip() or None), key, value),
        )
        conn.commit()
        conn.close()

    def test_extract_user_facts_normalizes_name_and_reminder(self):
        extract_user_facts("Chamo-me Rafael!!!", user_id="user-1")
        extract_user_facts("Lembra-te que tenho consulta amanha...", user_id="user-1")

        facts = load_facts(user_id="user-1")

        self.assertEqual(facts["name"], "Rafael")
        self.assertEqual(facts["reminders"], ["tenho consulta amanha"])

    def test_extract_user_facts_normalizes_preference_text(self):
        extract_user_facts(
            "Sempre que eu pedir o tempo quero que respondas para Caldas da Rainha...",
            user_id="user-1",
        )

        facts = load_facts(user_id="user-1")

        self.assertEqual(
            facts["preferences"],
            ["Sempre que eu pedir o tempo, quero que respondas para caldas da rainha."],
        )

    @patch(
        "memory.extract.call_llm",
        return_value=(
            '{"should_store": true, "name": "", '
            '"preferences": ["prefiro respostas curtas e diretas"], '
            '"reminders": []}'
        ),
    )
    def test_extract_user_facts_uses_llm_for_free_form_preference(self, mock_call_llm):
        extract_user_facts(
            "Prefiro respostas curtas e diretas.",
            user_id="user-1",
        )

        facts = load_facts(user_id="user-1")

        self.assertEqual(
            facts["preferences"],
            ["Prefiro respostas curtas e diretas."],
        )
        mock_call_llm.assert_called_once()

    @patch(
        "memory.extract.call_llm",
        return_value=(
            '{"should_store": true, "name": "", '
            '"preferences": [], '
            '"reminders": ["tenho consulta no dentista na sexta"]}'
        ),
    )
    def test_extract_user_facts_uses_llm_for_free_form_reminder(self, mock_call_llm):
        extract_user_facts(
            "Nao te esquecas da minha consulta no dentista na sexta.",
            user_id="user-1",
        )

        facts = load_facts(user_id="user-1")

        self.assertEqual(
            facts["reminders"],
            ["tenho consulta no dentista na sexta"],
        )
        mock_call_llm.assert_called_once()

    @patch(
        "memory.extract.call_llm",
        return_value=(
            '{"should_store": true, "name": "", '
            '"preferences": ["responde de forma curta daqui para a frente"], '
            '"reminders": []}'
        ),
    )
    def test_extract_user_facts_uses_llm_for_non_formulaic_preference_instruction(self, mock_call_llm):
        extract_user_facts(
            "Daqui para a frente responde de forma curta.",
            user_id="user-1",
        )

        facts = load_facts(user_id="user-1")

        self.assertEqual(
            facts["preferences"],
            ["Responde de forma curta daqui para a frente."],
        )
        mock_call_llm.assert_called_once()

    def test_load_facts_orders_preferences_and_reminders_by_numeric_index(self):
        self._insert_preference(10, "pref 10", user_id="user-1")
        self._insert_preference(2, "pref 2", user_id="user-1")
        self._insert_preference(1, "pref 1", user_id="user-1")
        self._insert_reminder(12, "rem 12", user_id="user-1")
        self._insert_reminder(3, "rem 3", user_id="user-1")
        self._insert_reminder(1, "rem 1", user_id="user-1")

        facts = load_facts(user_id="user-1")

        self.assertEqual(facts["preferences"], ["pref 1", "pref 2", "pref 10"])
        self.assertEqual(facts["reminders"], ["rem 1", "rem 3", "rem 12"])

    def test_delete_preference_uses_numeric_position(self):
        for index in range(1, 11):
            self._insert_preference(index, f"pref {index}", user_id="user-1")

        delete_preference(2, user_id="user-1")
        facts = load_facts(user_id="user-1")

        self.assertNotIn("pref 2", facts["preferences"])
        self.assertIn("pref 10", facts["preferences"])
        self.assertEqual(facts["preferences"][1], "pref 3")

    def test_delete_reminder_uses_numeric_position(self):
        for index in range(1, 11):
            self._insert_reminder(index, f"rem {index}", user_id="user-1")

        delete_reminder(2, user_id="user-1")
        facts = load_facts(user_id="user-1")

        self.assertNotIn("rem 2", facts["reminders"])
        self.assertIn("rem 10", facts["reminders"])
        self.assertEqual(facts["reminders"][1], "rem 3")

    def test_init_db_migrates_legacy_user_memory_to_split_tables(self):
        self._create_legacy_user_memory()
        self._insert_legacy_memory_entry("name", "Rafael", user_id="user-1")
        self._insert_legacy_memory_entry("assistant_name", "Daniel", user_id="user-1")
        self._insert_legacy_memory_entry("preference_2", "pref 2", user_id="user-1")
        self._insert_legacy_memory_entry("preference_1", "pref 1", user_id="user-1")
        self._insert_legacy_memory_entry("reminder_1", "rem 1", user_id="user-1")

        init_db()

        facts = load_facts(user_id="user-1")
        entries = list_memory_entries(user_id="user-1")
        keys = {entry["key"] for entry in entries}

        self.assertEqual(facts["name"], "Rafael")
        self.assertEqual(facts["assistant_name"], "Daniel")
        self.assertEqual(facts["preferences"], ["pref 1", "pref 2"])
        self.assertEqual(facts["reminders"], ["rem 1"])
        self.assertNotIn("assistant_name", keys)
        self.assertIn("preference_1", keys)
        self.assertIn("preference_2", keys)
        self.assertIn("reminder_1", keys)

    def test_list_memory_entries_excludes_settings_but_load_facts_keeps_them(self):
        self._insert_fact("name", "Rafael", user_id="user-1")
        update_settings(
            {
                "assistant_name": "Daniel",
                "llm_provider": "openai",
            },
            user_id="user-1",
        )

        entries = list_memory_entries(user_id="user-1")
        facts = load_facts(user_id="user-1")
        keys = {entry["key"] for entry in entries}

        self.assertEqual(keys, {"name"})
        self.assertEqual(facts["name"], "Rafael")
        self.assertEqual(facts["assistant_name"], "Daniel")
        self.assertEqual(facts["llm_provider"], "openai")

    def test_clear_memory_only_removes_semantic_memory_for_target_user(self):
        self._insert_fact("name", "Rafael", user_id="user-1")
        self._insert_preference(1, "pref 1", user_id="user-1")
        self._insert_reminder(1, "rem 1", user_id="user-1")
        self._insert_fact("name", "Maria", user_id="user-2")
        update_settings({"assistant_name": "Daniel"}, user_id="user-1")
        update_settings({"assistant_name": "Friday"}, user_id="user-2")

        deleted_count = clear_memory(user_id="user-1")

        user_1_facts = load_facts(user_id="user-1")
        user_2_facts = load_facts(user_id="user-2")
        user_1_entries = list_memory_entries(user_id="user-1")
        user_2_entries = list_memory_entries(user_id="user-2")

        self.assertEqual(deleted_count, 3)
        self.assertEqual(user_1_entries, [])
        self.assertEqual(user_1_facts["preferences"], [])
        self.assertEqual(user_1_facts["reminders"], [])
        self.assertEqual(user_1_facts["assistant_name"], "Daniel")
        self.assertEqual(user_2_facts["name"], "Maria")
        self.assertEqual(user_2_facts["assistant_name"], "Friday")
        self.assertEqual(len(user_2_entries), 1)
        self.assertEqual(user_2_entries[0]["key"], "name")

    def test_update_and_delete_memory_entry_support_split_tables(self):
        update_memory_entry("name", "Rafael", user_id="user-1")
        update_memory_entry("preference_5", "pref 5", user_id="user-1")
        update_memory_entry("reminder_2", "rem 2", user_id="user-1")

        facts = load_facts(user_id="user-1")
        entries = list_memory_entries(user_id="user-1")

        self.assertEqual(facts["name"], "Rafael")
        self.assertEqual(facts["preferences"], ["pref 5"])
        self.assertEqual(facts["reminders"], ["rem 2"])
        self.assertEqual(
            [entry["key"] for entry in entries],
            ["name", "preference_5", "reminder_2"],
        )

        self.assertTrue(delete_memory_entry("preference_5", user_id="user-1"))
        self.assertTrue(delete_memory_entry("reminder_2", user_id="user-1"))
        self.assertTrue(delete_memory_entry("name", user_id="user-1"))
        self.assertFalse(delete_memory_entry("name", user_id="user-1"))

        facts_after_delete = load_facts(user_id="user-1")
        self.assertEqual(facts_after_delete["preferences"], [])
        self.assertEqual(facts_after_delete["reminders"], [])
        self.assertEqual(list_memory_entries(user_id="user-1"), [])

    def test_update_memory_entry_rejects_settings_keys(self):
        with self.assertRaisesRegex(ValueError, "/settings"):
            update_memory_entry("assistant_name", "Daniel", user_id="user-1")

    def test_delete_memory_entry_rejects_settings_keys(self):
        with self.assertRaisesRegex(ValueError, "/settings"):
            delete_memory_entry("assistant_name", user_id="user-1")


if __name__ == "__main__":
    unittest.main()
