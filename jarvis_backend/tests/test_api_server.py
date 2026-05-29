from dataclasses import replace
import sqlite3
import tempfile
from types import SimpleNamespace
import unittest
from pathlib import Path
import re
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

    @patch("api.server.update_memory_entry", side_effect=ValueError("As configuracoes da conta devem ser alteradas pelo endpoint /settings."))
    def test_put_memory_rejects_settings_keys(self, mock_update_memory_entry):
        response = self.client.put(
            "/memory/assistant_name",
            headers=self.auth_headers(),
            json={"value": "Daniel"},
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("/settings", response.json()["detail"])
        mock_update_memory_entry.assert_called_once_with("assistant_name", "Daniel", user_id=None)

    @patch("api.server.delete_memory_entry", side_effect=ValueError("As configuracoes da conta devem ser removidas pelo endpoint /settings."))
    def test_delete_memory_rejects_settings_keys(self, mock_delete_memory_entry):
        response = self.client.delete(
            "/memory/assistant_name",
            headers=self.auth_headers(),
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("/settings", response.json()["detail"])
        mock_delete_memory_entry.assert_called_once_with("assistant_name", user_id=None)

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

    @patch.object(
        server.agent_gateway,
        "dispatch_action",
        new_callable=AsyncMock,
        return_value={
            "ok": False,
            "device_id": "pc-escritorio",
            "result": None,
            "error": "Timeout ao esperar resposta do agente pc-escritorio.",
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
    def test_chat_returns_honest_failure_when_connected_agent_action_fails(self, mock_chat, mock_dispatch):
        response = self.client.post(
            "/chat",
            headers=self.auth_headers(),
            json={"session_id": "sess-1", "message": "abre o spotify"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.json()["client_action"])
        self.assertEqual(response.json()["tool_result"]["tool_name"], "open_app")
        self.assertFalse(response.json()["tool_result"]["ok"])
        self.assertIn("falhou", response.json()["reply"].lower())
        self.assertIn("timeout ao esperar resposta", response.json()["reply"].lower())
        mock_dispatch.assert_awaited_once()
        mock_chat.assert_called_once()

    @patch.object(
        server.agent_gateway,
        "dispatch_action",
        new_callable=AsyncMock,
        return_value={
            "ok": False,
            "result": None,
            "error": "Nenhum agente executor ligado com capacidade desktop.control.",
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
    def test_chat_keeps_client_action_for_local_fallback_when_no_agent_is_connected(self, mock_chat, mock_dispatch):
        response = self.client.post(
            "/chat",
            headers=self.auth_headers(),
            json={"session_id": "sess-1", "message": "abre o spotify"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["reply"], "A abrir o Spotify.")
        self.assertIsNone(response.json()["tool_result"])
        self.assertEqual(response.json()["client_action"]["action"], "open_app")
        mock_dispatch.assert_awaited_once()
        mock_chat.assert_called_once()


class ApiServerMemoryFlowTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.temp_dir.name) / "api-memory-flow-tests.db"
        self.client = TestClient(server.app)
        self.original_settings = server.settings
        server.settings = replace(server.settings, api_token="test-token")
        server.assistant.sessions.clear()
        self.memory_connect_patcher = patch(
            "memory.user_memory._connect",
            side_effect=self._connect_to_temp_db,
        )
        self.settings_connect_patcher = patch(
            "settings_store.connect",
            side_effect=self._connect_to_temp_db,
        )
        self.resolve_auth_session_patcher = patch(
            "api.server.resolve_auth_session",
            side_effect=self._resolve_auth_session,
        )
        self.memory_connect_patcher.start()
        self.settings_connect_patcher.start()
        self.resolve_auth_session_patcher.start()

    def tearDown(self):
        self.memory_connect_patcher.stop()
        self.settings_connect_patcher.stop()
        self.resolve_auth_session_patcher.stop()
        server.assistant.sessions.clear()
        server.settings = self.original_settings
        self.temp_dir.cleanup()

    def _connect_to_temp_db(self):
        conn = sqlite3.connect(self.db_path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn

    def _resolve_auth_session(self, token: str):
        mapping = {
            "session-user-1": (
                SimpleNamespace(token="session-user-1", user_id="user-1"),
                SimpleNamespace(
                    id="user-1",
                    email="rafael@example.com",
                    display_name="Rafael",
                    created_at="2026-05-02T12:00:00+00:00",
                    email_verified_at="2026-05-02T12:05:00+00:00",
                    email_verified=True,
                ),
            ),
            "session-user-2": (
                SimpleNamespace(token="session-user-2", user_id="user-2"),
                SimpleNamespace(
                    id="user-2",
                    email="maria@example.com",
                    display_name="Maria",
                    created_at="2026-05-02T12:00:00+00:00",
                    email_verified_at="2026-05-02T12:05:00+00:00",
                    email_verified=True,
                ),
            ),
        }
        return mapping.get(token)

    def auth_headers(self, token: str = "session-user-1") -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

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

    def test_chat_flow_persists_name_and_reminder_and_lists_them_later(self):
        with patch("assistant.service.call_llm", side_effect=["Claro, fica guardado.", "Combinado."]):
            session_response = self.client.post("/sessions", headers=self.auth_headers())
            self.assertEqual(session_response.status_code, 200)
            session_id = session_response.json()["session_id"]

            name_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Chamo-me Rafael"},
            )
            reminder_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Lembra-te que tenho consulta amanha"},
            )

        memory_list_response = self.client.get("/memory", headers=self.auth_headers())
        memory_show_response = self.client.post(
            "/chat",
            headers=self.auth_headers(),
            json={"session_id": session_id, "message": "mostra memoria"},
        )

        self.assertEqual(name_response.status_code, 200)
        self.assertEqual(name_response.json()["reply"], "Claro, fica guardado.")
        self.assertEqual(reminder_response.status_code, 200)
        self.assertEqual(reminder_response.json()["reply"], "Combinado.")
        self.assertEqual(memory_list_response.status_code, 200)
        self.assertEqual(memory_show_response.status_code, 200)

        memory_entries = memory_list_response.json()
        self.assertEqual(
            [(entry["key"], entry["value"]) for entry in memory_entries],
            [("name", "Rafael"), ("reminder_1", "tenho consulta amanha")],
        )
        self.assertIn("Nome guardado: Rafael", memory_show_response.json()["reply"])
        self.assertIn("Lembretes:", memory_show_response.json()["reply"])
        self.assertIn("1. tenho consulta amanha", memory_show_response.json()["reply"])

    def test_chat_flow_uses_saved_weather_preference_and_keeps_user_memory_isolated(self):
        with patch("assistant.service.call_llm", side_effect=["Perfeito, vou guardar isso.", "Hoje em Caldas da Rainha esta sol."]):
            session_user_1 = self.client.post("/sessions", headers=self.auth_headers("session-user-1"))
            self.assertEqual(session_user_1.status_code, 200)
            session_id_user_1 = session_user_1.json()["session_id"]

            preference_response = self.client.post(
                "/chat",
                headers=self.auth_headers("session-user-1"),
                json={
                    "session_id": session_id_user_1,
                    "message": "Sempre que eu pedir o tempo quero que respondas para Caldas da Rainha",
                },
            )

            with patch(
                "assistant.service.execute_tool",
                return_value={
                    "tool_name": "get_weather",
                    "ok": True,
                    "data": {"city": "caldas da rainha", "forecast": "sol"},
                },
            ) as mock_execute_tool:
                weather_response = self.client.post(
                    "/chat",
                    headers=self.auth_headers("session-user-1"),
                    json={"session_id": session_id_user_1, "message": "como esta o tempo hoje"},
                )

        user_1_memory_response = self.client.get("/memory", headers=self.auth_headers("session-user-1"))
        user_2_memory_response = self.client.get("/memory", headers=self.auth_headers("session-user-2"))

        self.assertEqual(preference_response.status_code, 200)
        self.assertEqual(preference_response.json()["reply"], "Perfeito, vou guardar isso.")
        self.assertEqual(weather_response.status_code, 200)
        self.assertEqual(weather_response.json()["reply"], "Hoje em Caldas da Rainha esta sol.")
        mock_execute_tool.assert_called_once_with(
            "get_weather",
            {"city": "caldas da rainha", "day_offset": 0},
        )

        self.assertEqual(
            [(entry["key"], entry["value"]) for entry in user_1_memory_response.json()],
            [
                (
                    "preference_1",
                    "Sempre que eu pedir o tempo, quero que respondas para caldas da rainha.",
                )
            ],
        )
        self.assertEqual(user_2_memory_response.json(), [])

    def test_chat_flow_recalls_name_and_reminder_with_natural_questions(self):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            session_response = self.client.post("/sessions", headers=self.auth_headers())
            self.assertEqual(session_response.status_code, 200)
            session_id = session_response.json()["session_id"]

            self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Chamo-me Rafael"},
            )
            self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Lembra-te que tenho consulta amanha"},
            )

            name_recall_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Lembras-te do meu nome?"},
            )
            reminder_recall_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={
                    "session_id": session_id,
                    "message": "O que e que te pedi para te lembrares?",
                },
            )

        self.assertEqual(name_recall_response.status_code, 200)
        self.assertEqual(name_recall_response.json()["reply"], "Sim. Chamas-te Rafael.")
        self.assertEqual(reminder_recall_response.status_code, 200)
        self.assertEqual(
            reminder_recall_response.json()["reply"],
            "Pediste-me para me lembrar que tens consulta amanha.",
        )

    def test_chat_flow_updates_name_after_user_correction(self):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            session_response = self.client.post("/sessions", headers=self.auth_headers())
            self.assertEqual(session_response.status_code, 200)
            session_id = session_response.json()["session_id"]

            self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Chamo-me Rafael"},
            )
            self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Afinal chamo-me Rui"},
            )
            recall_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Qual e o meu nome agora?"},
            )

        self.assertEqual(recall_response.status_code, 200)
        self.assertEqual(recall_response.json()["reply"], "Sim. Chamas-te Rui.")

    def test_chat_flow_removes_latest_reminder_from_natural_phrase(self):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            session_response = self.client.post("/sessions", headers=self.auth_headers())
            self.assertEqual(session_response.status_code, 200)
            session_id = session_response.json()["session_id"]

            self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Lembra-te que tenho consulta amanha"},
            )
            removal_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Ja nao preciso desse lembrete"},
            )
            recall_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={
                    "session_id": session_id,
                    "message": "O que e que te pedi para te lembrares?",
                },
            )
            memory_response = self.client.get("/memory", headers=self.auth_headers())

        self.assertEqual(removal_response.status_code, 200)
        self.assertEqual(removal_response.json()["reply"], "Removi o lembrete mais recente da memoria.")
        self.assertEqual(recall_response.status_code, 200)
        self.assertEqual(recall_response.json()["reply"], "Nao tenho nenhum lembrete teu guardado.")
        self.assertEqual(memory_response.status_code, 200)
        self.assertEqual(memory_response.json(), [])

    def test_chat_flow_uses_latest_weather_preference_after_change_of_mind(self):
        with patch(
            "assistant.service.call_llm",
            side_effect=[
                "Primeira preferencia guardada.",
                "Segunda preferencia guardada.",
                "Tempo final.",
            ],
        ):
            session_response = self.client.post("/sessions", headers=self.auth_headers())
            self.assertEqual(session_response.status_code, 200)
            session_id = session_response.json()["session_id"]

            self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={
                    "session_id": session_id,
                    "message": "Sempre que eu pedir o tempo quero que respondas para Caldas da Rainha",
                },
            )
            self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={
                    "session_id": session_id,
                    "message": "Afinal quando eu pedir o tempo quero que respondas para Lisboa",
                },
            )

            with patch(
                "assistant.service.execute_tool",
                return_value={
                    "tool_name": "get_weather",
                    "ok": True,
                    "data": {"city": "Lisboa", "forecast": "sol"},
                },
            ) as mock_execute_tool:
                weather_response = self.client.post(
                    "/chat",
                    headers=self.auth_headers(),
                    json={"session_id": session_id, "message": "como esta o tempo hoje"},
                )

        self.assertEqual(weather_response.status_code, 200)
        self.assertEqual(weather_response.json()["reply"], "Tempo final.")
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
    def test_chat_flow_can_store_free_form_preference_via_llm_extraction(self, mock_extract_llm):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            session_response = self.client.post("/sessions", headers=self.auth_headers())
            self.assertEqual(session_response.status_code, 200)
            session_id = session_response.json()["session_id"]

            chat_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Prefiro respostas curtas e diretas."},
            )
            recall_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Que tipo de respostas prefiro?"},
            )
            memory_response = self.client.get("/memory", headers=self.auth_headers())

        self.assertEqual(chat_response.status_code, 200)
        self.assertEqual(chat_response.json()["reply"], "Resposta generica.")
        self.assertEqual(recall_response.status_code, 200)
        self.assertEqual(recall_response.json()["reply"], "Preferes respostas curtas e diretas.")
        self.assertEqual(
            [(entry["key"], entry["value"]) for entry in memory_response.json()],
            [("preference_1", "Prefiro respostas curtas e diretas.")],
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
    def test_chat_flow_can_store_non_formulaic_preference_instruction(self, mock_extract_llm):
        with patch("assistant.service.call_llm", side_effect=self._memory_aware_llm):
            session_response = self.client.post("/sessions", headers=self.auth_headers())
            self.assertEqual(session_response.status_code, 200)
            session_id = session_response.json()["session_id"]

            chat_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={
                    "session_id": session_id,
                    "message": "Daqui para a frente responde de forma curta.",
                },
            )
            recall_response = self.client.post(
                "/chat",
                headers=self.auth_headers(),
                json={"session_id": session_id, "message": "Que tipo de respostas prefiro?"},
            )
            memory_response = self.client.get("/memory", headers=self.auth_headers())

        self.assertEqual(chat_response.status_code, 200)
        self.assertIn("responde de forma curta", recall_response.json()["reply"].lower())
        self.assertEqual(
            [(entry["key"], entry["value"]) for entry in memory_response.json()],
            [("preference_1", "Responde de forma curta daqui para a frente.")],
        )
        mock_extract_llm.assert_called()


if __name__ == "__main__":
    unittest.main()
