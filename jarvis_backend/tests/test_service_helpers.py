import unittest

from assistant.service import (
    build_client_action,
    extract_youtube_playback_action,
    extract_youtube_query,
    extract_youtube_request,
    extract_youtube_result_index,
    matches_close_tab_command,
    matches_close_window_command,
    matches_memory_clear_command,
)


class ServiceHelperTests(unittest.TestCase):
    def test_matches_memory_clear_command_requires_clear_intent(self):
        self.assertTrue(matches_memory_clear_command("limpa a memoria"))
        self.assertTrue(matches_memory_clear_command("esquecer preferencias antigas"))
        self.assertFalse(matches_memory_clear_command("memoria"))
        self.assertFalse(matches_memory_clear_command("limpa isto"))

    def test_build_client_action_normalizes_url_and_open_app(self):
        open_url = build_client_action(
            {"tool_name": "open_website", "arguments": {"url": "example.com"}}
        )
        open_youtube = build_client_action(
            {"tool_name": "open_app", "arguments": {"app_name": "youtube"}}
        )
        open_app = build_client_action(
            {"tool_name": "open_app", "arguments": {"app_name": "spotify"}}
        )

        self.assertEqual(open_url, {"type": "open_url", "url": "https://example.com"})
        self.assertEqual(
            open_youtube,
            {"type": "open_url", "url": "https://www.youtube.com"},
        )
        self.assertEqual(
            open_app,
            {"type": "open_app", "app_name": "spotify"},
        )

    def test_build_client_action_handles_generic_desktop_controls(self):
        close_app = build_client_action(
            {
                "tool_name": "control_computer",
                "arguments": {"action": "close_app", "target": "Spotify"},
            }
        )
        close_tab = build_client_action(
            {
                "tool_name": "control_computer",
                "arguments": {"action": "close_browser_tab"},
            }
        )
        youtube_search = build_client_action(
            {
                "tool_name": "control_computer",
                "arguments": {"action": "play_youtube", "query": "Daft Punk"},
            }
        )
        youtube_pause = build_client_action(
            {
                "tool_name": "control_computer",
                "arguments": {"action": "pause_youtube"},
            }
        )

        self.assertEqual(
            close_app,
            {
                "type": "pc_action",
                "action": "close_app",
                "arguments": {"app_name": "Spotify"},
            },
        )
        self.assertEqual(
            close_tab,
            {
                "type": "pc_action",
                "action": "close_tab",
                "arguments": {},
            },
        )
        self.assertEqual(
            youtube_search,
            {
                "type": "pc_action",
                "action": "youtube_play",
                "arguments": {"query": "Daft Punk"},
            },
        )
        self.assertEqual(
            youtube_pause,
            {
                "type": "pc_action",
                "action": "youtube_pause",
                "arguments": {},
            },
        )

    def test_build_client_action_infers_close_tab_and_youtube_search(self):
        close_tab = build_client_action(
            {
                "tool_name": "control_computer",
                "arguments": {"action": "fechar a aba do youtube"},
            }
        )
        youtube_search = build_client_action(
            {
                "tool_name": "control_computer",
                "arguments": {"action": "abrir musica no youtube", "query": "Muse Uprising"},
            }
        )

        self.assertEqual(
            close_tab,
            {
                "type": "pc_action",
                "action": "close_tab",
                "arguments": {},
            },
        )
        self.assertEqual(
            youtube_search,
            {
                "type": "pc_action",
                "action": "youtube_play",
                "arguments": {"query": "Muse Uprising"},
            },
        )

    def test_matches_close_window_command_requires_window_intent_only(self):
        self.assertTrue(matches_close_window_command("fecha a janela"))
        self.assertTrue(matches_close_window_command("fechar esta janela ativa"))
        self.assertFalse(matches_close_window_command("fecha a aplicacao spotify"))
        self.assertFalse(matches_close_window_command("fecha a aba do chrome"))

    def test_matches_close_tab_command_detects_tab_requests(self):
        self.assertTrue(matches_close_tab_command("fecha a aba do youtube"))
        self.assertTrue(matches_close_tab_command("fechar esta tab"))
        self.assertFalse(matches_close_tab_command("fecha a janela do chrome"))

    def test_extract_youtube_query_handles_music_requests(self):
        self.assertEqual(
            extract_youtube_query("abre uma musica dos metallica no youtube"),
            "metallica",
        )
        self.assertEqual(
            extract_youtube_query("toca bohemian rhapsody no youtube"),
            "bohemian rhapsody",
        )
        self.assertEqual(
            extract_youtube_query("abre o youtube e mete uma musica calma"),
            "musica calma",
        )
        self.assertIsNone(extract_youtube_query("abre o google"))

    def test_extract_youtube_request_distinguishes_search_from_play(self):
        self.assertEqual(
            extract_youtube_request("pesquisa lo fi no youtube"),
            {"action": "youtube_search", "query": "lo fi", "result_index": 1},
        )
        self.assertEqual(
            extract_youtube_request("mete uma musica calma no youtube"),
            {"action": "youtube_play", "query": "musica calma", "result_index": 1},
        )

    def test_extract_youtube_result_index_handles_ordinal_commands(self):
        self.assertEqual(extract_youtube_result_index("abre a segunda musica"), 2)
        self.assertEqual(extract_youtube_result_index("toca o terceiro video do youtube"), 3)
        self.assertIsNone(extract_youtube_result_index("abre o youtube"))

    def test_extract_youtube_playback_action_detects_pause_and_resume(self):
        self.assertEqual(
            extract_youtube_playback_action("poe o video do youtube na pausa"),
            "youtube_pause",
        )
        self.assertEqual(
            extract_youtube_playback_action("retoma o video do youtube"),
            "youtube_resume",
        )
        self.assertIsNone(extract_youtube_playback_action("abre o youtube"))


if __name__ == "__main__":
    unittest.main()
