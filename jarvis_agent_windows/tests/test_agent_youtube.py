import unittest
from unittest.mock import Mock, patch

import agent


class AgentYoutubeTests(unittest.TestCase):
    def test_extract_youtube_video_ids_keeps_unique_order(self):
        html = '''
        {"videoId":"AAAAAAAAAAA"}
        {"videoId":"BBBBBBBBBBB"}
        {"videoId":"AAAAAAAAAAA"}
        '''

        self.assertEqual(
            agent._extract_youtube_video_ids(html),
            ["AAAAAAAAAAA", "BBBBBBBBBBB"],
        )

    @patch("agent.urllib.request.urlopen")
    def test_resolve_youtube_video_url_returns_requested_result(self, mock_urlopen):
        mock_response = mock_urlopen.return_value.__enter__.return_value
        mock_response.read.return_value = (
            b'{"videoId":"AAAAAAAAAAA"}{"videoId":"BBBBBBBBBBB"}'
        )

        resolved = agent._resolve_youtube_video_url("musica calma", result_index=2)

        self.assertEqual(
            resolved,
            "https://www.youtube.com/watch?v=BBBBBBBBBBB&autoplay=1",
        )

    @patch("agent.webbrowser.open")
    @patch("agent._resolve_youtube_video_url", return_value="https://www.youtube.com/watch?v=BBBBBBBBBBB&autoplay=1")
    def test_play_youtube_opens_direct_video_url(self, mock_resolve, mock_open):
        result = agent._play_youtube("musica calma", result_index=2)

        self.assertTrue(result["ok"])
        self.assertEqual(result["result_index"], 2)
        self.assertEqual(result["url"], "https://www.youtube.com/watch?v=BBBBBBBBBBB&autoplay=1")
        mock_resolve.assert_called_once_with("musica calma", 2)
        mock_open.assert_called_once_with("https://www.youtube.com/watch?v=BBBBBBBBBBB&autoplay=1")

    @patch("agent.pyautogui.press")
    @patch("agent._find_windows")
    def test_control_youtube_playback_activates_window_and_presses_k(self, mock_find_windows, mock_press):
        window = Mock()
        window.title = "Musica calma - YouTube - Google Chrome"
        window.isMinimized = False
        mock_find_windows.return_value = [window]

        result = agent._control_youtube_playback("pause")

        self.assertTrue(result["ok"])
        self.assertEqual(result["state"], "pause")
        self.assertEqual(result["keys"], "k")
        window.activate.assert_called_once()
        mock_press.assert_called_once_with("k")

    @patch("agent._find_windows", return_value=[])
    def test_control_youtube_playback_fails_without_youtube_window(self, mock_find_windows):
        result = agent._control_youtube_playback("pause")

        self.assertFalse(result["ok"])
        self.assertIn("youtube", result["error"].lower())


if __name__ == "__main__":
    unittest.main()
