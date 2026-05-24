from dataclasses import replace
from types import SimpleNamespace
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
        self.assertIn("email_enabled", response.json())

    @patch("api.server.count_users", return_value=1)
    def test_health_reports_auth_enabled_when_users_exist_without_api_token(self, mock_count_users):
        server.settings = replace(server.settings, api_token="")

        response = self.client.get("/health")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["auth_enabled"])
        mock_count_users.assert_called()

    def test_sessions_require_auth_when_token_is_configured(self):
        response = self.client.post("/sessions")

        self.assertEqual(response.status_code, 401)

    @patch("api.server.send_registration_email")
    @patch(
        "api.server.create_email_code",
        return_value=SimpleNamespace(code="123456"),
    )
    @patch(
        "api.server.create_user",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at=None,
        ),
    )
    def test_register_sends_verification_email(self, mock_create_user, mock_create_email_code, mock_send_email):
        response = self.client.post(
            "/auth/register",
            json={
                "email": "rafael@example.com",
                "password": "segredo123",
                "display_name": "Rafael",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["verification_required"])
        self.assertTrue(response.json()["email_sent"])
        self.assertEqual(response.json()["email"], "rafael@example.com")
        mock_create_user.assert_called_once_with(
            email="rafael@example.com",
            password="segredo123",
            display_name="Rafael",
        )
        mock_create_email_code.assert_called_once_with(
            user_id="user-1",
            email="rafael@example.com",
            purpose="verify_email",
        )
        mock_send_email.assert_called_once()

    @patch(
        "api.server.authenticate_user",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at="2026-05-02T12:05:00+00:00",
            email_verified=True,
        ),
    )
    @patch("api.server.create_auth_session", return_value=SimpleNamespace(token="session-2"))
    def test_login_returns_session_payload(self, mock_create_session, mock_authenticate):
        response = self.client.post(
            "/auth/login",
            json={
                "email": "rafael@example.com",
                "password": "segredo123",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["access_token"], "session-2")
        self.assertEqual(response.json()["user"]["display_name"], "Rafael")
        mock_authenticate.assert_called_once_with("rafael@example.com", "segredo123")
        mock_create_session.assert_called_once_with("user-1")

    @patch(
        "api.server.authenticate_user",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at=None,
            email_verified=False,
        ),
    )
    def test_login_rejects_unverified_user(self, mock_authenticate):
        response = self.client.post(
            "/auth/login",
            json={
                "email": "rafael@example.com",
                "password": "segredo123",
            },
        )

        self.assertEqual(response.status_code, 403)
        self.assertIn("confirmar o email", response.json()["detail"])
        mock_authenticate.assert_called_once_with("rafael@example.com", "segredo123")

    @patch("api.server.create_auth_session", return_value=SimpleNamespace(token="session-verify"))
    @patch(
        "api.server.mark_user_email_verified",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at="2026-05-02T12:15:00+00:00",
            email_verified=True,
        ),
    )
    @patch(
        "api.server.consume_email_code",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at=None,
            email_verified=False,
        ),
    )
    def test_verify_email_returns_session(self, mock_consume, mock_mark_verified, mock_create_session):
        response = self.client.post(
            "/auth/verify-email",
            json={"email": "rafael@example.com", "code": "123456"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["access_token"], "session-verify")
        mock_consume.assert_called_once_with(
            email="rafael@example.com",
            purpose="verify_email",
            code="123456",
        )
        mock_mark_verified.assert_called_once_with("user-1")
        mock_create_session.assert_called_once_with("user-1")

    @patch("api.server.send_password_reset_email")
    @patch(
        "api.server.create_email_code",
        return_value=SimpleNamespace(code="654321"),
    )
    @patch(
        "api.server.get_user_by_email",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at="2026-05-02T12:05:00+00:00",
            email_verified=True,
        ),
    )
    def test_forgot_password_sends_email(self, mock_get_user, mock_create_email_code, mock_send_email):
        response = self.client.post(
            "/auth/forgot-password",
            json={"email": "rafael@example.com"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["email_sent"])
        mock_get_user.assert_called_once_with("rafael@example.com")
        mock_create_email_code.assert_called_once_with(
            user_id="user-1",
            email="rafael@example.com",
            purpose="reset_password",
        )
        mock_send_email.assert_called_once()

    @patch(
        "api.server.update_user_password",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at="2026-05-02T12:05:00+00:00",
            email_verified=True,
        ),
    )
    @patch(
        "api.server.consume_email_code",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at="2026-05-02T12:05:00+00:00",
            email_verified=True,
        ),
    )
    def test_reset_password_updates_password(self, mock_consume, mock_update_password):
        response = self.client.post(
            "/auth/reset-password",
            json={
                "email": "rafael@example.com",
                "code": "654321",
                "new_password": "segredo-novo",
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["ok"])
        mock_consume.assert_called_once_with(
            email="rafael@example.com",
            purpose="reset_password",
            code="654321",
        )
        mock_update_password.assert_called_once_with("user-1", "segredo-novo")

    @patch(
        "api.server.get_user_by_id",
        return_value=SimpleNamespace(
            id="user-1",
            email="rafael@example.com",
            display_name="Rafael",
            created_at="2026-05-02T12:00:00+00:00",
            email_verified_at="2026-05-02T12:05:00+00:00",
            email_verified=True,
        ),
    )
    @patch(
        "api.server.resolve_auth_session",
        return_value=(
            SimpleNamespace(token="session-3", user_id="user-1"),
            SimpleNamespace(
                id="user-1",
                email="rafael@example.com",
                display_name="Rafael",
                created_at="2026-05-02T12:00:00+00:00",
                email_verified_at="2026-05-02T12:05:00+00:00",
                email_verified=True,
            ),
        ),
    )
    def test_auth_me_returns_authenticated_user(self, mock_resolve_session, mock_get_user):
        response = self.client.get(
            "/auth/me",
            headers={"Authorization": "Bearer session-3"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["id"], "user-1")
        self.assertEqual(response.json()["email"], "rafael@example.com")
        mock_resolve_session.assert_called_once_with("session-3")
        mock_get_user.assert_called_once_with("user-1")

    @patch("api.server.revoke_auth_session")
    @patch(
        "api.server.resolve_auth_session",
        return_value=(
            SimpleNamespace(token="session-4", user_id="user-1"),
            SimpleNamespace(
                id="user-1",
                email="rafael@example.com",
                display_name="Rafael",
                created_at="2026-05-02T12:00:00+00:00",
                email_verified_at="2026-05-02T12:05:00+00:00",
                email_verified=True,
            ),
        ),
    )
    def test_auth_logout_revokes_session_token(self, mock_resolve_session, mock_revoke_session):
        response = self.client.post(
            "/auth/logout",
            headers={"Authorization": "Bearer session-4"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["ok"])
        mock_resolve_session.assert_called_once_with("session-4")
        mock_revoke_session.assert_called_once_with("session-4")

    @patch.object(
        server.assistant,
        "create_session",
        return_value={
            "session_id": "sess-1",
            "tools": [{"name": "get_weather"}],
            "desktop_tools_enabled": True,
        },
    )
    def test_create_session_with_bearer_token(self, mock_create_session):
        response = self.client.post("/sessions", headers=self.auth_headers())

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["session_id"], "sess-1")
        self.assertTrue(response.json()["desktop_tools_enabled"])
        mock_create_session.assert_called_once()

    @patch.object(
        server.assistant,
        "chat",
        return_value={
            "session_id": "sess-1",
            "reply": "Ola",
            "tool_result": None,
            "desktop_tools_enabled": True,
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
        self.assertTrue(response.json()["desktop_tools_enabled"])
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
        mock_delete.assert_called_once_with("media_player.tv", user_id=None)

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
        mock_resolve.assert_called_once_with("Televisao", domain="media_player", user_id=None)
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
        mock_update_settings.assert_called_once_with(
            {
                "assistant_name": "Daniel",
                "user_name": "Rafael",
                "wake_word_phrase": "Daniel",
                "wake_word_sensitivity": 40,
                "llm_provider": "ollama",
                "ollama_url": "",
                "ollama_model": "",
                "openai_model": "",
                "openai_api_key": "",
                "home_assistant_enabled": False,
                "home_assistant_url": "",
                "home_assistant_token": "",
            },
            user_id=None,
        )

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
            "desktop_tools_enabled": True,
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
