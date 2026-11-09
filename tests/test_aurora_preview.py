from contextlib import closing
from datetime import timedelta
import unittest

import numpy as np
from skyfield.api import load, load_file

from astronomy import utc
from observatory.aurora.aurora import ROOT, calculate, kp_blocks


class AuroraPreviewTests(unittest.TestCase):
    def test_dark_model_sightline_and_expiry(self):
        now = utc("2026-11-10T02:00:00Z")
        place = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}
        cells = np.array([[-86, 41, 50], [-87, 41, 50], [-88, 41, 50]])
        observed = now - timedelta(minutes=5)
        valid = now + timedelta(minutes=35)
        ts = load.timescale(builtin=True)
        with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
            active = calculate(eph, ts, place, now, (observed, valid, cells), [])
            stale = calculate(eph, ts, place, now + timedelta(hours=2), (observed, valid, cells), [])
            day = now + timedelta(hours=14)
            daylight = calculate(eph, ts, place, day, (day, day + timedelta(minutes=30), cells), [])
        self.assertEqual(active["current"]["verdict"], "possible")
        self.assertEqual(active["current"]["look"]["direction"], "N")
        self.assertEqual(stale["current"]["verdict"], "uncertain")
        self.assertNotIn("look", stale["current"])
        self.assertEqual(daylight["current"]["verdict"], "daylight")

    def test_kp_object_and_legacy_rows_match(self):
        record = {"time_tag": "2026-11-10T00:00:00", "kp": "5.67", "observed": "predicted"}
        self.assertEqual(kp_blocks([record]), kp_blocks([list(record), list(record.values())]))
