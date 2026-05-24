import unittest
from unittest.mock import patch

from llm.ollama import LLMUnavailableError
from llm.service import call_llm, resolve_llm_settings


class LlmServiceTests(unittest.TestCase):
    @patch(
        "llm.service.load_settings_values",
        return_value={
            "llm_provider": "openai",
            "ollama_url": "http://127.0.0.1:11434",
            "ollama_model": "llama3.1:8b",
            "openai_model": "gpt-4.1-mini",
            "openai_api_key": "sk-test",
        },
    )
    def test_resolve_llm_settings_uses_user_values(self, mock_load_settings):
        resolved = resolve_llm_settings(user_id="user-1")

        self.assertEqual(resolved["provider"], "openai")
        self.assertEqual(resolved["openai_model"], "gpt-4.1-mini")
        self.assertEqual(resolved["openai_api_key"], "sk-test")
        mock_load_settings.assert_called_once_with(user_id="user-1")

    @patch("llm.service.call_openai_llm", return_value="Resposta OpenAI")
    @patch(
        "llm.service.load_settings_values",
        return_value={
            "llm_provider": "openai",
            "ollama_url": "http://127.0.0.1:11434",
            "ollama_model": "llama3.1:8b",
            "openai_model": "gpt-4.1-mini",
            "openai_api_key": "sk-test",
        },
    )
    def test_call_llm_routes_to_openai_when_provider_is_openai(self, _mock_settings, mock_openai):
        reply = call_llm(
            [{"role": "user", "content": "Ola"}],
            user_id="user-1",
        )

        self.assertEqual(reply, "Resposta OpenAI")
        mock_openai.assert_called_once_with(
            [{"role": "user", "content": "Ola"}],
            model="gpt-4.1-mini",
            api_key="sk-test",
        )

    @patch("llm.service.call_ollama_llm", return_value="Resposta Ollama")
    @patch(
        "llm.service.load_settings_values",
        return_value={
            "llm_provider": "ollama",
            "ollama_url": "http://localhost:11434",
            "ollama_model": "mistral",
            "openai_model": "gpt-4.1-mini",
            "openai_api_key": "",
        },
    )
    def test_call_llm_routes_to_ollama_by_default(self, _mock_settings, mock_ollama):
        reply = call_llm(
            [{"role": "user", "content": "Ola"}],
            user_id=None,
        )

        self.assertEqual(reply, "Resposta Ollama")
        mock_ollama.assert_called_once_with(
            [{"role": "user", "content": "Ola"}],
            model="mistral",
            ollama_url="http://localhost:11434",
        )


class OpenAiProviderValidationTests(unittest.TestCase):
    def test_openai_without_api_key_raises_helpful_error(self):
        with patch.dict("os.environ", {}, clear=True):
            from llm.openai import call_llm as call_openai_llm

            with self.assertRaises(LLMUnavailableError) as context:
                call_openai_llm(
                    [{"role": "user", "content": "Ola"}],
                    model="gpt-4.1-mini",
                    api_key="",
                )

        self.assertIn("OpenAI sem chave API configurada", str(context.exception))


if __name__ == "__main__":
    unittest.main()
