from contextlib import closing
from datetime import timedelta
import unittest

from skyfield.api import load, load_file

from astronomy import utc
from observatory.planets.planets import ROOT, calculate


class PlanetPreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.now = utc("2026-11-09T12:00:00Z")
        site = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}
        with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
            cls.result = calculate(eph, load.timescale(builtin=True), site, cls.now)

    def test_mars_and_jupiter_match_nasa_november_guide(self):
        pair = next(item for item in self.result["pairings"] if item["name"] == "Mars and Jupiter")
        self.assertEqual(utc(pair["peak"]).day, 16)
        self.assertAlmostEqual(pair["separation"], 1.2, delta=0.05)
        window = pair["window"]
        self.assertLess(window["start"], window["time"])
        self.assertLess(window["time"], window["end"])
        self.assertTrue(all(item["altitude"] >= 10 for item in window["positions"]))

    def test_upcoming_windows_stay_within_the_forecast_and_hide_low_mercury(self):
        mercury = next(item for item in self.result["highlights"] if item["name"] == "Mercury")
        self.assertEqual(mercury["windows"], [])
        for planet in self.result["highlights"]:
            for window in planet["windows"]:
                self.assertGreaterEqual(utc(window["start"]), self.now.replace(microsecond=0))
                self.assertLessEqual(utc(window["end"]), self.now + timedelta(days=1))
        pair = next(item for item in self.result["pairings"] if item["name"] == "Mercury and Moon")
        self.assertIsNone(pair["window"])
