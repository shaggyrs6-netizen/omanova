from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from observatory.events.launches import FEED, normalise, prepare
from worker import read, write


class LaunchPreviewTest(unittest.TestCase):
    def test_normalises_precision_hold_and_stream(self):
        result, = normalise({"results": [{
            "id": "421785e3-d1b4-4874-ae34-344a24fa2a03",
            "name": "  Vulcan   ·   Demonstration  ",
            "net": "2026-11-13T14:00:00-06:00",
            "net_precision": {"abbrev": "MIN"},
            "status": {"id": 5, "name": "Hold"},
            "vid_urls": [{"url": "javascript:alert(1)"}, {"url": "https://example.org/webcast"}],
        }]})
        self.assertEqual(result["net"], "2026-11-13T20:00:00Z")
        self.assertEqual(result["status"], "Hold")
        self.assertEqual(result["stream"], "https://example.org/webcast")
        self.assertTrue(result["source"].startswith("https://ll.thespacedevs.com/2.3.0/launches/"))

    def test_fixture_is_offline_and_includes_tentative_and_held_launches(self):
        with TemporaryDirectory() as tmp, patch("observatory.events.launches.get_json") as fetch:
            prepare(Path(tmp), fixture=True)
            fetch.assert_not_called()
            data = read(Path(tmp) / "launches.json", {})
        self.assertTrue(data["fixture"])
        self.assertEqual([row["statusId"] for row in data["launches"]], [1, 8, 5])
        self.assertEqual(data["launches"][1]["precision"], "DAY")

    def test_throttle_preserves_cached_schedule_and_prevents_retry(self):
        with TemporaryDirectory() as tmp:
            state = Path(tmp)
            prepare(state, fixture=True)
            cache = {"data": {"results": [{
                "id": "421785e3-d1b4-4874-ae34-344a24fa2a03", "name": "Held launch",
                "status": {"id": 5, "name": "Hold"},
            }]}, "fetched": "2026-11-09T00:00:00Z"}
            write(state / "launch-cache-detailed.json", cache)
            error = HTTPError(FEED, 429, "throttled", {"Retry-After": "3600"}, None)
            with patch("observatory.events.launches.DEFAULT_STATE", state), patch(
                "observatory.events.launches.get_json", side_effect=error
            ) as fetch:
                write(state / "settings.json", {"launches": "true"})
                prepare(state, fixture=False)
                fetch.assert_not_called()
                paused = read(state / "launches.json", {})
                self.assertFalse(paused["enabled"])
                self.assertEqual(paused["launches"][0]["name"], "Held launch")
                write(state / "settings.json", {"launches": True})
                prepare(state, fixture=False)
                prepare(state, fixture=False)
                fetch.assert_called_once_with(FEED)
            data = read(state / "launches.json", {})
            self.assertEqual(data["error"], "HTTP 429")
            self.assertEqual(data["launches"][0]["name"], "Held launch")
