from dataclasses import replace
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import api.server as server


class ApiServerTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(server.app)
        self.original_settings = server.settings
        server.settings = replace(server.settings, api_token="test-token")

    def tearDown(self):
        server.settings = self.original_settings

    def auth_headers(self) -> dict[str, str]:
        return {"Authorization": "Bearer test-token"}

    def test_health_does_not_require_auth(self):
        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")
        self.assertTrue(response.json()["auth_enabled"])

    def test_sessions_require_auth_when_token_is_configured(self):
        response = self.client.post("/sessions")

        self.assertEqual(response.status_code, 401)

    @patch.object(
        server.assistant,
        "create_session",
        return_value={
            "session_id": "sess-1",
            "tools": [{"name": "get_weather"}],
            "desktop_tools_enabled": False,
        },
    )
    def test_create_session_with_bearer_token(self, mock_create_session):
        response = self.client.post("/sessions", headers=self.auth_headers())

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["session_id"], "sess-1")
        mock_create_session.assert_called_once()

    @patch.object(
        server.assistant,
        "chat",
        return_value={
            "session_id": "sess-1",
            "reply": "Ola",
            "tool_result": None,
            "desktop_tools_enabled": False,
            "client_action": None,
        },
    )
    def test_chat_returns_payload_when_authorized(self, mock_chat):
        response = self.client.post(
            "/chat",
            headers=self.auth_headers(),
            json={"session_id": "sess-1", "message": "Ola"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["reply"], "Ola")
        mock_chat.assert_called_once_with("sess-1", "Ola")

    @patch.object(server.assistant, "chat", side_effect=KeyError("Sessao desconhecida: sess-404"))
    def test_chat_maps_missing_session_to_404(self, mock_chat):
        response = self.client.post(
            "/chat",
            headers=self.auth_headers(),
            json={"session_id": "sess-404", "message": "Ola"},
        )

        self.assertEqual(response.status_code, 404)
        self.assertIn("Sessao desconhecida", response.json()["detail"])
        mock_chat.assert_called_once()

    def test_memory_requires_auth(self):
        response = self.client.get("/memory")

        self.assertEqual(response.status_code, 401)

    @patch("api.server.synthesize_speech", return_value="ZmFrZS1hdWRpbw==")
    def test_tts_works_with_auth(self, mock_tts):
        response = self.client.post(
            "/tts",
            headers=self.auth_headers(),
            json={"text": "ola"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["audio"], "ZmFrZS1hdWRpbw==")
        mock_tts.assert_called_once_with("ola")


if __name__ == "__main__":
    unittest.main()
