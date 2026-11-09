from contextlib import closing
from pathlib import Path
import unittest

from skyfield.api import load, load_file

from astronomy import utc
from observatory.orbit.tracks import build, ground_distance
from worker import read

ROOT = Path(__file__).resolve().parents[1]


class OrbitPreviewTest(unittest.TestCase):
    def test_ground_distance_wraps_at_antimeridian(self):
        self.assertAlmostEqual(ground_distance(0, 179, 0, -179), 222.39, delta=0.1)
        self.assertEqual(ground_distance(36, -86, 36, -86), 0)

    def test_both_tracks_match_pass_geometry(self):
        rows = read(ROOT / "tests/fixtures/stations.json", [])
        place = {"id": "fixture", "lat": 36.1627, "lon": -86.7816, "elevation": 0}
        with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as ephemeris:
            stations = build(rows, place, utc("2026-11-09T23:26Z"), ephemeris, load.timescale())
        self.assertEqual([station["name"] for station in stations], ["ISS", "Tiangong"])
        for station in stations:
            passes = station["passes"]
            self.assertTrue(passes)
            self.assertIn(station["preferred"], [event["id"] for event in passes])
            for event in passes:
                self.assertGreater(len(event["track"]), 200)
                self.assertTrue(all(abs(lat) <= 90 and abs(lon) <= 180 for lon, lat in event["track"]))
                points = event["pass"]
                self.assertEqual(points[0]["time"], event["rise"])
                self.assertEqual(points[-1]["time"], event["set"])
                peak = next(point for point in points if point["time"] == event["peak"])
                self.assertGreaterEqual(peak["el"], max(point["el"] for point in points) - 0.1)
                self.assertGreater(peak["slant"], peak["altitude"] - 1)
                self.assertGreaterEqual(peak["ground"], 0)
