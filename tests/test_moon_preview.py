from pathlib import Path
import unittest

from skyfield.api import load, load_file, wgs84

from astronomy import utc
from observatory.moon.moon import calculate, full_moon_details, phase_name

ROOT = Path(__file__).resolve().parents[1]
NOW = utc("2026-11-09T12:00:00Z")
NASHVILLE = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}


class MoonPreviewTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ts = load.timescale(builtin=True)
        cls.eph = load_file(str(ROOT / "assets/de440s.bsp"))
        cls.addClassCleanup(cls.eph.close)
        cls.moon = calculate(cls.eph, cls.ts, NASHVILLE, NOW)

    def test_phase_and_illumination_near_new_moon(self):
        self.assertEqual(self.moon["phase"], "Waxing crescent")
        self.assertTrue(0 < self.moon["illumination"] < 0.01)
        self.assertEqual([phase_name(i) for i in (0, 90, 180, 270)],
                         ["New Moon", "First Quarter", "Full Moon", "Last Quarter"])

    def test_next_full_moon_agrees_with_usno_and_can_be_below_local_horizon(self):
        # USNO primary-phase table for 2026-11-09, 4 phases, reports 14:53 UTC.
        full = self.moon["full"]
        reference = utc("2026-11-24T14:53:00Z")
        self.assertLess(abs((utc(full["time"]) - reference).total_seconds()), 60)
        self.assertLess(full["el"], 0)
        self.assertTrue(full["windows"])

    def test_local_windows_use_both_moon_and_sun_altitude(self):
        observer = self.eph["earth"] + wgs84.latlon(NASHVILLE["lat"], NASHVILLE["lon"])
        for window in self.moon["nextWindows"] + self.moon["full"]["windows"]:
            self.assertLessEqual(window["start"]["time"], window["peak"]["time"])
            self.assertLessEqual(window["peak"]["time"], window["end"]["time"])
            self.assertGreaterEqual(window["peak"]["el"], 5)
            t = self.ts.from_datetime(utc(window["peak"]["time"]))
            sun_alt = observer.at(t).observe(self.eph["sun"]).apparent().altaz()[0].degrees
            self.assertLessEqual(sun_alt, -5.99)

    def test_named_full_moons_use_orbit_relative_distance(self):
        cases = (
            ("2026-05-31T09:45:00Z", "Blue Moon", "Micromoon"),
            ("2026-09-26T16:49:00Z", "Harvest Moon", "Neither supermoon nor micromoon"),
            ("2026-10-26T04:12:00Z", "Hunter’s Moon", "Neither supermoon nor micromoon"),
            (self.moon["full"]["time"], "Beaver Moon", "Supermoon"),
        )
        for stamp, name, size in cases:
            with self.subTest(stamp=stamp):
                details = full_moon_details(self.eph, self.ts, utc(stamp))
                self.assertEqual((details["name"], details["size"]), (name, size))
        self.assertAlmostEqual(details["distanceKm"], 360766, delta=3)

    def test_polar_no_dark_window_is_valid(self):
        summer = utc("2026-06-20T12:00:00Z")
        result = calculate(self.eph, self.ts, {"lat": 85, "lon": 15, "elevation": 0}, summer)
        self.assertFalse(result["nextWindows"])
        self.assertFalse(result["full"]["windows"])
