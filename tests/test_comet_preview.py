from contextlib import closing
import json
import unittest

from skyfield.api import load, load_file

from astronomy import utc
from observatory.comets.comets import CATALOG, ROOT, calculate


class CometPreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(CATALOG.read_text())
        cls.nashville = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}

    def calculate_at(self, date):
        with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
            return calculate(eph, load.timescale(builtin=True), self.nashville, utc(date), self.catalog)

    def test_hartley_first_window_agrees_with_topocentric_horizons(self):
        result = self.calculate_at("2026-11-09T12:00:00Z")
        target = next(item for item in result["targets"] if item["name"] == "161P/Hartley-IRAS")
        self.assertEqual(target["equipment"], "telescope")
        look = target["windows"][0]
        self.assertLess(look["start"], look["time"])
        self.assertLess(look["time"], look["end"])
        self.assertLess(abs((utc(look["time"]) - utc("2026-11-10T00:13:00Z")).total_seconds()), 60)
        # Horizons quantity 4 for the public Nashville fixture at 00:13 UTC.
        self.assertAlmostEqual(look["azimuth"], 242.37, delta=1)
        self.assertAlmostEqual(look["altitude"], 55.69, delta=1)
        self.assertTrue(look["moonDown"])

    def test_expired_catalog_produces_no_windows(self):
        result = self.calculate_at(self.catalog["until"])
        self.assertFalse(result["available"])
        self.assertEqual(result["targets"], [])
