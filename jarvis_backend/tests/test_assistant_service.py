import unittest

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

    def test_youtube_request_returns_search_action(self):
        response = self.assistant.chat(
            self.session_id,
            "toca musica dos queen no youtube",
        )

        self.assertEqual(response["reply"], "A pesquisar no YouTube.")
        self.assertEqual(response["client_action"]["action"], "youtube_search")
        self.assertEqual(response["client_action"]["arguments"]["query"], "queen")

    def test_time_question_is_answered_without_tool_call(self):
        response = self.assistant.chat(self.session_id, "que horas sao")

        self.assertTrue(response["reply"])
        self.assertIsNone(response["tool_call"])
        self.assertIsNone(response["client_action"])


if __name__ == "__main__":
    unittest.main()
