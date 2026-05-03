import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from memory.extract import extract_user_facts
from memory.user_memory import (
    delete_preference,
    delete_reminder,
    init_db,
    load_facts,
)


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

    def _insert_memory_entry(self, key: str, value: str, user_id: str | None = None):
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

    def test_load_facts_orders_preferences_and_reminders_by_numeric_index(self):
        self._insert_memory_entry("preference_10", "pref 10", user_id="user-1")
        self._insert_memory_entry("preference_2", "pref 2", user_id="user-1")
        self._insert_memory_entry("preference_1", "pref 1", user_id="user-1")
        self._insert_memory_entry("reminder_12", "rem 12", user_id="user-1")
        self._insert_memory_entry("reminder_3", "rem 3", user_id="user-1")
        self._insert_memory_entry("reminder_1", "rem 1", user_id="user-1")

        facts = load_facts(user_id="user-1")

        self.assertEqual(facts["preferences"], ["pref 1", "pref 2", "pref 10"])
        self.assertEqual(facts["reminders"], ["rem 1", "rem 3", "rem 12"])

    def test_delete_preference_uses_numeric_position(self):
        for index in range(1, 11):
            self._insert_memory_entry(
                f"preference_{index}",
                f"pref {index}",
                user_id="user-1",
            )

        delete_preference(2, user_id="user-1")
        facts = load_facts(user_id="user-1")

        self.assertNotIn("pref 2", facts["preferences"])
        self.assertIn("pref 10", facts["preferences"])
        self.assertEqual(facts["preferences"][1], "pref 3")

    def test_delete_reminder_uses_numeric_position(self):
        for index in range(1, 11):
            self._insert_memory_entry(
                f"reminder_{index}",
                f"rem {index}",
                user_id="user-1",
            )

        delete_reminder(2, user_id="user-1")
        facts = load_facts(user_id="user-1")

        self.assertNotIn("rem 2", facts["reminders"])
        self.assertIn("rem 10", facts["reminders"])
        self.assertEqual(facts["reminders"][1], "rem 3")


if __name__ == "__main__":
    unittest.main()
