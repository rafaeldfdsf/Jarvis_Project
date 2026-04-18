import unittest

from tools.registry import available_tools


class AvailableToolsTests(unittest.TestCase):
    def test_api_mode_excludes_local_keyboard_automation_only(self):
        tool_names = {tool["name"] for tool in available_tools(enable_local_automation=False)}

        self.assertIn("open_app", tool_names)
        self.assertIn("open_website", tool_names)
        self.assertIn("control_computer", tool_names)
        self.assertIn("analyze_screen", tool_names)
        self.assertNotIn("type_text", tool_names)
        self.assertNotIn("press_keys", tool_names)


if __name__ == "__main__":
    unittest.main()