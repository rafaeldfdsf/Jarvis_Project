from dataclasses import replace
import unittest
from unittest.mock import AsyncMock, patch

from fastapi.testclient import TestClient

import api.server as server
from home_assistant.service import call_service


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

    @patch("api.server.connection_status", return_value={
        "configured": True,
        "connected": True,
        "url": "http://192.168.1.163:8123",
        "location_name": "Casa",
        "entity_count": 12,
        "message": "Ligacao ao Home Assistant ativa.",
    })
    def test_home_assistant_status_with_auth(self, mock_status):
        response = self.client.get(
            "/home-assistant/status",
            headers=self.auth_headers(),
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["connected"])
        mock_status.assert_called_once()

    @patch(
        "api.server.list_devices",
        return_value=[
            {
                "entity_id": "light.sala",
                "domain": "light",
                "friendly_name": "Luz Sala",
                "alias": "luz da sala",
                "state": "on",
                "attributes": {},
                "last_seen_at": "2026-04-18T12:00:00+00:00",
                "updated_at": "2026-04-18T12:00:00+00:00",
            }
        ],
    )
    def test_home_assistant_devices_with_auth(self, mock_devices):
        response = self.client.get(
            "/home-assistant/devices",
            headers=self.auth_headers(),
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()[0]["alias"], "luz da sala")
        mock_devices.assert_called_once()

    @patch("api.server.delete_device", return_value=True)
    def test_delete_home_assistant_device_with_auth(self, mock_delete):
        response = self.client.delete(
            "/home-assistant/devices/media_player.tv",
            headers=self.auth_headers(),
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["deleted"])
        mock_delete.assert_called_once_with("media_player.tv")

    @patch(
        "home_assistant.service.resolve_device_reference",
        return_value={
            "entity_id": "media_player.vodafone_tv_4_2",
            "alias": "Televisao",
        },
    )
    @patch("home_assistant.service._request", return_value=[])
    def test_call_service_resolves_alias_to_entity_id(self, mock_request, mock_resolve):
        result = call_service(
            "media_player",
            "turn_off",
            entity_id="Televisao",
        )

        self.assertEqual(result["entity_id"], "media_player.vodafone_tv_4_2")
        self.assertEqual(result["resolved_from"], "Televisao")
        mock_resolve.assert_called_once_with("Televisao", domain="media_player")
        mock_request.assert_called_once()

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

    @patch("api.server.list_settings", return_value=[
        {
            "key": "assistant_name",
            "value": "Daniel",
            "label": "Nome do Assistente",
            "updated_at": "2026-05-02T12:00:00+00:00",
        }
    ])
    def test_get_settings_with_auth(self, mock_list_settings):
        response = self.client.get("/settings", headers=self.auth_headers())

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()[0]["value"], "Daniel")
        mock_list_settings.assert_called_once()

    @patch("api.server.update_settings", return_value=[
        {
            "key": "assistant_name",
            "value": "Daniel",
            "label": "Nome do Assistente",
            "updated_at": "2026-05-02T12:00:00+00:00",
        }
    ])
    def test_put_settings_with_auth(self, mock_update_settings):
        response = self.client.put(
            "/settings",
            headers=self.auth_headers(),
            json={
                "assistant_name": "Daniel",
                "user_name": "Rafael",
                "wake_word_phrase": "Daniel",
                "wake_word_sensitivity": 40,
                "home_assistant_enabled": False,
                "home_assistant_url": "",
                "home_assistant_token": "",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()[0]["key"], "assistant_name")
        mock_update_settings.assert_called_once()

    @patch("api.server.list_registered_devices", return_value=[
        {
            "device_id": "pc-escritorio",
            "name": "PC Escritorio",
            "device_type": "windows",
            "platform": "windows",
            "location": "escritorio",
            "is_active": True,
            "preferred_for_wake_word": False,
            "preferred_for_tts": False,
            "preferred_for_desktop_control": True,
            "connected": True,
            "last_seen_at": "2026-05-02T12:00:00+00:00",
            "last_error": "",
            "metadata": {},
            "capabilities": ["desktop.control"],
            "created_at": "2026-05-02T12:00:00+00:00",
            "updated_at": "2026-05-02T12:00:00+00:00",
        }
    ])
    def test_get_devices_with_auth(self, mock_list_devices):
        response = self.client.get("/devices", headers=self.auth_headers())

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()[0]["device_id"], "pc-escritorio")
        mock_list_devices.assert_called_once()

    @patch.object(
        server.agent_gateway,
        "dispatch_action",
        new_callable=AsyncMock,
        return_value={
            "ok": True,
            "device_id": "pc-escritorio",
            "result": {"ok": True, "app": "spotify"},
            "error": None,
        },
    )
    @patch.object(
        server.assistant,
        "chat",
        return_value={
            "session_id": "sess-1",
            "reply": "A abrir o Spotify.",
            "tool_result": None,
            "desktop_tools_enabled": False,
            "client_action": {
                "type": "pc_action",
                "action": "open_app",
                "arguments": {"app_name": "spotify"},
            },
        },
    )
    def test_chat_dispatches_client_action_to_connected_agent(self, mock_chat, mock_dispatch):
        response = self.client.post(
            "/chat",
            headers=self.auth_headers(),
            json={"session_id": "sess-1", "message": "abre o spotify"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.json()["client_action"])
        self.assertEqual(response.json()["tool_result"]["tool_name"], "open_app")
        mock_dispatch.assert_awaited_once()
        mock_chat.assert_called_once()


if __name__ == "__main__":
    unittest.main()
