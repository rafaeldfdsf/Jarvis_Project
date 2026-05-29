import sqlite3
import tempfile
import unittest
from pathlib import Path
import re
from unittest.mock import patch

from assistant.service import AssistantService


class AssistantServiceCommandTests(unittest.TestCase):
    def setUp(self):
        self.assistant = AssistantService(enable_desktop_tools=True)
        created = self.assistant.create_session()
        self.session_id = created["session_id"]

    def test_create_session_reports_desktop_tools_enabled(self):
        created = self.assistant.create_session()

        self.assertTrue(created["desktop_tools_enabled"])
        self.assertTrue(any(tool["name"] == "control_computer" for tool in created["tools"]))

    def test_close_window_command_returns_pc_action(self):
        response = self.assistant.chat(self.session_id, "fecha esta janela")

        self.assertEqual(response["reply"], "A fechar a janela.")
        self.assertEqual(response["client_action"]["type"], "pc_action")
        self.assertEqual(response["client_action"]["action"], "close_window")

    def test_youtube_request_returns_play_action(self):
        response = self.assistant.chat(
            self.session_id,
            "toca musica dos queen no youtube",
        )

        self.assertEqual(response["reply"], "A por a tocar no YouTube.")
        self.assertEqual(response["client_action"]["action"], "youtube_play")
        self.assertEqual(response["client_action"]["arguments"]["query"], "queen")
        self.assertEqual(response["client_action"]["arguments"]["result_index"], 1)

    def test_youtube_follow_up_uses_last_query_for_second_result(self):
        first_response = self.assistant.chat(
            self.session_id,
            "abre o youtube e mete uma musica calma",
        )
        second_response = self.assistant.chat(
            self.session_id,
            "abre a segunda musica",
        )

        self.assertEqual(first_response["client_action"]["action"], "youtube_play")
        self.assertEqual(first_response["client_action"]["arguments"]["query"], "musica calma")
        self.assertEqual(second_response["reply"], "A abrir o resultado 2 do YouTube.")
        self.assertEqual(second_response["client_action"]["action"], "youtube_play")
        self.assertEqual(second_response["client_action"]["arguments"]["query"], "musica calma")
        self.assertEqual(second_response["client_action"]["arguments"]["result_index"], 2)

    def test_youtube_pause_command_returns_pause_action(self):
        response = self.assistant.chat(
            self.session_id,
            "poe o video do youtube na pausa",
        )

        self.assertEqual(response["reply"], "A pausar o video do YouTube.")
        self.assertEqual(response["client_action"]["action"], "youtube_pause")
        self.assertEqual(response["client_action"]["arguments"], {})

    def test_youtube_resume_command_returns_resume_action(self):
        response = self.assistant.chat(
            self.session_id,
            "retoma o video do youtube",
        )

        self.assertEqual(response["reply"], "A retomar o video do YouTube.")
        self.assertEqual(response["client_action"]["action"], "youtube_resume")
        self.assertEqual(response["client_action"]["arguments"], {})

    def test_time_question_is_answered_without_tool_call(self):
        response = self.assistant.chat(self.session_id, "que horas sao")

        self.assertTrue(response["reply"])
        self.assertIsNone(response["tool_call"])
        self.assertIsNone(response["client_action"])


class AssistantServiceMemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "assistant-memory-tests.db"
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
        self.assistant = AssistantService(enable_desktop_tools=False)
        created = self.assistant.create_session(user_id="user-1")
        self.session_id = created["session_id"]

    def tearDown(self):
        self.memory_connect_patcher.stop()
        self.settings_connect_patcher.stop()
        self.temp_dir.cleanup()

    def _connect_to_temp_db(self):
        conn = sqlite3.connect(self.db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn

    def _memory_aware_llm(self, messages, user_id=None):
        system_prompt = messages[0]["content"]
        last_user_message = ""
        for message in reversed(messages):
            if message.get("role") == "user":
                last_user_message = str(message.get("content") or "").lower()
                break

        name_match = re.search(r"Sabes que o utilizador chama-se (.+?)\.", system_prompt)
        remembered_name = name_match.group(1).strip() if name_match else ""
        remembered_reminders = re.findall(r"- (.+)", system_prompt.split("Lembretes importantes:\n", 1)[1]) if "Lembretes importantes:\n" in system_prompt else []
        remembered_preferences = re.findall(r"- (.+)", system_prompt.split("Preferencias do utilizador:\n", 1)[1]) if "Preferencias do utilizador:\n" in system_prompt else []

        def as_second_person(text: str) -> str:
            return (
                text.replace("tenho ", "tens ")
                .replace("estou ", "estas ")
                .replace("vou ", "vais ")
            )

        def preference_reply(text: str) -> str:
            normalized = text.rstrip(".").strip()
            if normalized.lower().startswith("prefiro "):
                return "Preferes " + normalized[8:].strip().lower() + "."
            return normalized + "."

        if "chamo-me rafael" in last_user_message:
            return "Claro, Rafael."
        if "afinal chamo-me rui" in last_user_message:
            return "Percebi. Passo a tratar-te por Rui."
        if "lembra-te que tenho consulta amanha" in last_user_message:
            return "Fica guardado."
        if "ja nao preciso desse lembrete" in last_user_message:
            return "Combinado, ja removi esse lembrete."
        if "lembras-te do meu nome" in last_user_message or "qual e o meu nome" in last_user_message:
            if remembered_name:
                return f"Sim. Chamas-te {remembered_name}."
            return "Ainda nao me disseste o teu nome."
        if "que tipo de respostas prefiro" in last_user_message:
            if remembered_preferences:
                return preference_reply(remembered_preferences[-1])
            return "Ainda nao me disseste nenhuma preferencia sobre isso."
        if "que lembretes tens meus" in last_user_message:
            if remembered_reminders:
                return "Tenho estes lembretes teus: " + "; ".join(remembered_reminders) + "."
            return "Nao tenho lembretes teus guardados."
        if "o que e que te pedi para te lembrares" in last_user_message or "do que te lembras" in last_user_message:
            if remembered_reminders:
                return "Pediste-me para me lembrar que " + as_second_person(remembered_reminders[-1]) + "."
            return "Nao tenho nenhum lembrete teu guardado."
        return "Resposta generica."

    def test_conversation_stores_name_and_remembers_it_in_later_session(self):
        with patch("assistant.service.call_llm", return_value="Tudo bem."):
            self.assistant.chat(self.session_id, "Chamo-me Rafael")

        same_session_memory = self.assistant.chat(self.session_id, "mostra memoria")
        created = self.assistant.create_session(user_id="user-1")
        later_session_memory = self.assistant.chat(created["session_id"], "mostra memoria")

        self.assertIn("Nome guardado: Rafael", same_session_memory["reply"])
        self.assertIn("Nome guardado: Rafael", later_session_memory["reply"])

    def test_conversation_stores_reminder_and_lists_it_later(self):
        with patch("assistant.service.call_llm", return_value="Fica guardado."):
            self.assistant.chat(
                self.session_id,
                "Lembra-te que tenho consulta amanha",
            )

        memory_response = self.assistant.chat(self.session_id, "mostra memoria")

        self.assertIn("Lembretes:", memory_response["reply"])
        self.assertIn("1. tenho consulta amanha", memory_response["reply"])

    def test_weather_request_uses_saved_preference_in_later_turn(self):
        with patch("assistant.service.call_llm", side_effect=["Perfeito.", "Tempo falso."]) as mock_call_llm:
            self.assistant.chat(
                self.session_id,
                "Sempre que eu pedir o tempo quero que respondas para Caldas da Rainha",
            )

            with patch(
                "assistant.service.execute_tool",
                return_value={
                    "tool_name": "get_weather",
                    "ok": True,
                    "data": {"city": "caldas da rainha", "forecast": "sol"},
                },
            ) as mock_execute_tool:
                weather_response = self.assistant.chat(self.session_id, "como esta o tempo hoje")

        self.assertEqual(weather_response["reply"], "Tempo falso.")
        mock_execute_tool.assert_called_once_with(
            "get_weather",
            {"city": "caldas da rainha", "day_offset": 0},
        )
        self.assertEqual(mock_call_llm.call_count, 2)

    def test_memory_clear_command_removes_saved_name_and_reminder(self):
        with patch("assistant.service.call_llm", return_value="Ok."):
            self.assistant.chat(self.session_id, "Chamo-me Rafael")
            self.assistant.chat(self.session_id, "Lembra-te que tenho consulta amanha")

        clear_response = self.assistant.chat(self.session_id, "limpa a memoria")
        memory_response = self.assistant.chat(self.session_id, "mostra memoria")

        self.assertEqual(clear_response["reply"], "Toda a memoria foi limpa.")
        self.assertNotIn("Nome guardado:", memory_response["reply"])
        self.assertIn("Nenhuma preferencia guardada.", memory_response["reply"])
        self.assertIn("Nenhum lembrete guardado.", memory_response["reply"])

    def test_conversation_recalls_name_via_natural_follow_up_question(self):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            self.assistant.chat(self.session_id, "Chamo-me Rafael")
            recall_response = self.assistant.chat(self.session_id, "Lembras-te do meu nome?")

        self.assertEqual(recall_response["reply"], "Sim. Chamas-te Rafael.")

    def test_conversation_recalls_reminder_via_natural_follow_up_question(self):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            self.assistant.chat(self.session_id, "Lembra-te que tenho consulta amanha")
            recall_response = self.assistant.chat(
                self.session_id,
                "O que e que te pedi para te lembrares?",
            )

        self.assertEqual(
            recall_response["reply"],
            "Pediste-me para me lembrar que tens consulta amanha.",
        )

    def test_conversation_updates_name_when_user_corrects_it(self):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            self.assistant.chat(self.session_id, "Chamo-me Rafael")
            self.assistant.chat(self.session_id, "Afinal chamo-me Rui")
            recall_response = self.assistant.chat(self.session_id, "Qual e o meu nome agora?")

        self.assertEqual(recall_response["reply"], "Sim. Chamas-te Rui.")

    def test_conversation_removes_latest_reminder_from_natural_phrase(self):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            self.assistant.chat(self.session_id, "Lembra-te que tenho consulta amanha")
            removal_response = self.assistant.chat(self.session_id, "Ja nao preciso desse lembrete")
            recall_response = self.assistant.chat(
                self.session_id,
                "O que e que te pedi para te lembrares?",
            )

        self.assertEqual(removal_response["reply"], "Removi o lembrete mais recente da memoria.")
        self.assertEqual(recall_response["reply"], "Nao tenho nenhum lembrete teu guardado.")

    def test_latest_weather_preference_wins_after_user_changes_mind(self):
        with patch("assistant.service.call_llm", side_effect=["Primeira preferencia guardada.", "Segunda preferencia guardada.", "Tempo final."]):
            self.assistant.chat(
                self.session_id,
                "Sempre que eu pedir o tempo quero que respondas para Caldas da Rainha",
            )
            self.assistant.chat(
                self.session_id,
                "Afinal quando eu pedir o tempo quero que respondas para Lisboa",
            )

            with patch(
                "assistant.service.execute_tool",
                return_value={
                    "tool_name": "get_weather",
                    "ok": True,
                    "data": {"city": "Lisboa", "forecast": "sol"},
                },
            ) as mock_execute_tool:
                response = self.assistant.chat(self.session_id, "como esta o tempo hoje")

        self.assertEqual(response["reply"], "Tempo final.")
        mock_execute_tool.assert_called_once_with(
            "get_weather",
            {"city": "Lisboa", "day_offset": 0},
        )

    @patch(
        "memory.extract.call_llm",
        return_value=(
            '{"should_store": true, "name": "", '
            '"preferences": ["prefiro respostas curtas e diretas"], '
            '"reminders": []}'
        ),
    )
    def test_conversation_can_store_preference_without_expected_regex_phrase(self, mock_extract_llm):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            self.assistant.chat(self.session_id, "Prefiro respostas curtas e diretas.")
            recall_response = self.assistant.chat(
                self.session_id,
                "Que tipo de respostas prefiro?",
            )

        self.assertEqual(
            recall_response["reply"],
            "Preferes respostas curtas e diretas.",
        )
        self.assertIn(
            "Prefiro respostas curtas e diretas.",
            self.assistant._get_session_state(self.session_id).messages[0]["content"],
        )
        mock_extract_llm.assert_called()

    @patch(
        "memory.extract.call_llm",
        return_value=(
            '{"should_store": true, "name": "", '
            '"preferences": ["responde de forma curta daqui para a frente"], '
            '"reminders": []}'
        ),
    )
    def test_conversation_can_store_non_formulaic_preference_instruction(self, mock_extract_llm):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            self.assistant.chat(self.session_id, "Daqui para a frente responde de forma curta.")
            recall_response = self.assistant.chat(
                self.session_id,
                "Que tipo de respostas prefiro?",
            )

        self.assertIn("responde de forma curta", recall_response["reply"].lower())
        self.assertIn(
            "Responde de forma curta daqui para a frente.",
            self.assistant._get_session_state(self.session_id).messages[0]["content"],
        )
        mock_extract_llm.assert_called()


if __name__ == "__main__":
    unittest.main()
