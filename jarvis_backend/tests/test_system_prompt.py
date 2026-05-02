import unittest
from unittest.mock import patch

from prompts.system_prompt import build_system_prompt


class SystemPromptTests(unittest.TestCase):
    @patch(
        "prompts.system_prompt.load_facts",
        return_value={
            "assistant_name": "Daniel",
            "wake_word_phrase": "Daniel",
            "home_assistant_url": "http://192.168.1.163:8123",
            "home_assistant_token": "abc123",
            "name": "Rafael",
            "preferences": ["gosta de respostas curtas"],
            "reminders": ["reuniao as 15h"],
        },
    )
    @patch(
        "prompts.system_prompt.device_alias_map",
        return_value={
            "light.sala": {
                "alias": "luz da sala",
                "friendly_name": "Luz Sala",
                "domain": "light",
            }
        },
    )
    def test_build_system_prompt_uses_custom_assistant_identity(self, _mock_aliases, _mock_load_facts):
        prompt = build_system_prompt(available_tools=[])

        self.assertIn("O teu nome de assistente e Daniel.", prompt)
        self.assertIn("A palavra de ativacao configurada e Daniel.", prompt)
        self.assertIn("O Home Assistant esta configurado em http://192.168.1.163:8123.", prompt)
        self.assertIn("light.sala", prompt)
        self.assertIn("luz da sala", prompt)
        self.assertIn("Sabes que o utilizador chama-se Rafael.", prompt)
        self.assertIn("gosta de respostas curtas", prompt)
        self.assertIn("reuniao as 15h", prompt)


if __name__ == "__main__":
    unittest.main()
