from datetime import timedelta
import json
from pathlib import Path
import unittest

import numpy as np
from skyfield.api import EarthSatellite, load, load_file, wgs84
from skyfield.positionlib import ICRF
from skyfield.units import Distance

from astronomy import predict, station_rows, utc

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures"
NOW = utc("2026-11-09T00:00Z")
NASHVILLE = {"id": "nashville", "lat": 36.1627, "lon": -86.7816, "elevation": 0}
SYDNEY = {"id": "sydney", "lat": -33.87, "lon": 151.21, "elevation": 0}


class AstronomyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = json.loads((FIXTURES / "stations.json").read_text())
        cls.ts = load.timescale(builtin=True)
        cls.eph = load_file(str(ROOT / "assets/de440s.bsp"))
        cls.addClassCleanup(cls.eph.close)
        cls.events = predict(cls.rows, cls.ts, cls.eph, NASHVILLE, NOW)
        cls.sydney = predict(cls.rows, cls.ts, cls.eph, SYDNEY, NOW, days=1)

    def event(self, station, prefix, events=None):
        return next(e for e in (self.events if events is None else events)
                    if e["name"] == station and e["start"].startswith(prefix))

    def test_iss_compared_to_nasa_oem(self):
        e = self.event("ISS", "2026-11-09T23:38")
        vectors = [line.split() for line in (FIXTURES / "nasa-iss-oem.txt").read_text().splitlines()
                   if not line.startswith("#")]
        anchor = utc(vectors[0][0])
        samples = np.array([[float(x) for x in v[1:]] for v in vectors])
        seconds = np.arange(0, 960)
        i = seconds // 240
        u = ((seconds % 240) / 240)[:, None]
        a, b = samples[i], samples[i + 1]
        # Cubic Hermite interpolation from NASA positions and velocities.
        xyz = ((2*u**3 - 3*u**2 + 1)*a[:, :3] + (u**3 - 2*u**2 + u)*240*a[:, 3:]
               + (-2*u**3 + 3*u**2)*b[:, :3] + (u**3 - u**2)*240*b[:, 3:])
        dates = [anchor + timedelta(seconds=int(sec)) for sec in seconds]
        t = self.ts.from_datetimes(dates)
        site = wgs84.latlon(NASHVILLE["lat"], NASHVILLE["lon"])
        topocentric = ICRF(Distance(km=xyz.T).au - site.at(t).xyz.au, t=t, center=site)
        alt, az, _ = topocentric.altaz()
        peak = int(np.argmax(alt.degrees))
        above = np.flatnonzero(alt.degrees >= 0)
        for key, index in (("start", above[0]), ("peak", peak), ("end", above[-1])):
            self.assertLessEqual(abs((dates[index] - utc(e[key])).total_seconds()), 15)
        self.assertAlmostEqual(e["culmination"]["el"], alt.degrees[peak], delta=1)
        self.assertAlmostEqual(e["culmination"]["az"], az.degrees[peak], delta=3)
        self.assertTrue(e["windows"])

    def test_iss_shadow_cuts_visible_window_before_culmination(self):
        e = self.event("ISS", "2026-11-09T00:26")
        window, = e["windows"]
        self.assertEqual(window["start"]["direction"], "SSW")
        self.assertLess(window["end"]["time"], e["peak"])
        self.assertEqual(window["start"]["time"], "2026-11-09T00:28:14Z")

    def test_tiangong_sydney_against_dense_geometry_scan(self):
        e = self.event("Tiangong", "2026-11-09T16:30", self.sydney)
        anchor = utc("2026-11-09T16:29Z")
        dates = [anchor + timedelta(seconds=i) for i in range(800)]
        t = self.ts.from_datetimes(dates)
        site = wgs84.latlon(SYDNEY["lat"], SYDNEY["lon"])
        sat = EarthSatellite.from_omm(self.ts, self.rows[1])
        altitude, bearing, _ = (sat - site).at(t).altaz()
        above = np.flatnonzero(altitude.degrees > 0)
        peak = np.argmax(altitude.degrees)
        for key, index in (("start", above[0]), ("peak", peak), ("end", above[-1])):
            self.assertLessEqual(abs((dates[index] - utc(e[key])).total_seconds()), 2)
        self.assertAlmostEqual(e["culmination"]["el"], 28.5, delta=0.1)
        self.assertAlmostEqual(e["culmination"]["az"], bearing.degrees[peak], delta=0.5)
        window, = e["windows"]
        self.assertEqual((window["start"]["direction"], window["end"]["direction"]), ("SSE", "ESE"))
        self.assertGreater(window["start"]["time"], e["start"])

    def test_daylight_shadow_low_and_high(self):
        for station, time, reason in (
            ("Tiangong", "2026-11-09T17:06", "too bright"),
            ("ISS", "2026-11-09T08:33", "Earth’s shadow"),
            ("ISS", "2026-11-09T03:41", "below 10°"),
        ):
            e = self.event(station, time)
            self.assertFalse(e["windows"])
            self.assertIn(reason, e["reason"])

    def test_stale_and_expired_orbits(self):
        self.assertTrue(any(e["confidence"] == "Stale orbit" for e in self.events))
        self.assertEqual(predict(self.rows, self.ts, self.eph, NASHVILLE, NOW + timedelta(days=8)), [])

    def test_malformed_orbit_rejected(self):
        with self.assertRaises(ValueError):
            station_rows([self.rows[0], dict(self.rows[1], MEAN_MOTION="nan")], self.ts)
