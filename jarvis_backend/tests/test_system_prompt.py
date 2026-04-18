import unittest
from unittest.mock import patch

from prompts.system_prompt import build_system_prompt


class SystemPromptTests(unittest.TestCase):
    @patch(
        "prompts.system_prompt.load_facts",
        return_value={
            "assistant_name": "Daniel",
            "wake_word_phrase": "Daniel",
            "name": "Rafael",
            "preferences": ["gosta de respostas curtas"],
            "reminders": ["reuniao as 15h"],
        },
    )
    def test_build_system_prompt_uses_custom_assistant_identity(self, _mock_load_facts):
        prompt = build_system_prompt(available_tools=[])

        self.assertIn("O teu nome de assistente e Daniel.", prompt)
        self.assertIn("A palavra de ativacao configurada e Daniel.", prompt)
        self.assertIn("Sabes que o utilizador chama-se Rafael.", prompt)
        self.assertIn("gosta de respostas curtas", prompt)
        self.assertIn("reuniao as 15h", prompt)


if __name__ == "__main__":
    unittest.main()
