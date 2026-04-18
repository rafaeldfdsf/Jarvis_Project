from datetime import datetime, timezone
import unittest

from tools.executor import parse_day


class ParseDayTests(unittest.TestCase):
    def test_parse_day_handles_relative_labels(self):
        now = datetime(2026, 4, 3, 9, 0, tzinfo=timezone.utc)

        self.assertEqual(parse_day("tempo hoje", now=now), 0)
        self.assertEqual(parse_day("tempo amanha", now=now), 1)
        self.assertEqual(parse_day("tempo depois de amanha", now=now), 2)

    def test_parse_day_uses_current_weekday_for_named_days(self):
        now = datetime(2026, 4, 3, 9, 0, tzinfo=timezone.utc)  # sexta-feira

        self.assertEqual(parse_day("tempo no sabado", now=now), 1)
        self.assertEqual(parse_day("tempo no domingo", now=now), 2)
        self.assertEqual(parse_day("tempo na quinta", now=now), 6)


if __name__ == "__main__":
    unittest.main()
