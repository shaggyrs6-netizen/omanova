import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from observatory.satellites.watchlist import prepare


class WatchlistPreviewTests(unittest.TestCase):
    def test_fixture_includes_non_station_viewing_windows(self):
        with TemporaryDirectory() as state:
            directory = Path(state)
            output = directory / "satellites.json"
            prepare(output, directory, fixture=True)
            snapshot = json.loads(output.read_text())

        self.assertTrue(snapshot["fixture"])
        self.assertEqual(len(snapshot["targets"]), 7)
        self.assertTrue(any(window["name"] == "Aqua" for window in snapshot["windows"]))
        for window in snapshot["windows"]:
            self.assertLess(window["start"]["time"], window["end"]["time"])
            self.assertTrue(window["peak"]["sunlit"])
            self.assertTrue(window["peak"]["sky_dark"])
            self.assertGreaterEqual(window["peak"]["el"], 10)
