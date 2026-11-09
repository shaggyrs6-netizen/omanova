from contextlib import closing
import unittest

from skyfield.api import load, load_file

from astronomy import utc
from observatory.eclipses.eclipses import ROOT, calculate


class EclipsePreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        nashville = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}
        with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
            cls.events = calculate(eph, load.timescale(builtin=True), nashville,
                                   utc("2026-11-09T12:00:00Z"))

    def assert_near(self, actual, expected):
        self.assertLess(abs((utc(actual) - utc(expected)).total_seconds()), 90)

    def test_nashville_partial_solar_eclipse(self):
        event = self.events["solar"][0]
        self.assertEqual(event["kind"], "partial")
        self.assertAlmostEqual(event["coverage"], 4.9, delta=0.2)
        self.assert_near(event["visible"][0]["start"], "2028-01-26T13:36:00Z")
        self.assert_near(event["peak"], "2028-01-26T14:21:00Z")
        self.assert_near(event["visible"][0]["end"], "2028-01-26T15:11:00Z")

    def test_lunar_moonrise_clipping_and_totality(self):
        first = self.events["lunar"][0]
        self.assertEqual(first["kind"], "penumbral")
        self.assertLess(first["peak"], first["visible"][0]["start"])
        self.assertGreater(first["look"]["time"], first["visible"][0]["start"])
        event = next(item for item in self.events["lunar"] if item["kind"] == "total")
        totality = event["central"][0]
        self.assert_near(totality["start"], "2029-06-26T02:31:08Z")
        self.assert_near(totality["end"], "2029-06-26T04:13:01Z")
