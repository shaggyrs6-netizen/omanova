from contextlib import closing
from datetime import timedelta
import unittest

from skyfield.api import load, load_file, wgs84

from astronomy import utc
from observatory.plumes.plumes import FIXTURE_ID, ROOT, TRACK_DIR, evaluate, validate_points, windows_for_track
from worker import DEMO_NOW, read


class PlumePreviewTests(unittest.TestCase):
    def setUp(self):
        ephemeris = load_file(str(ROOT / "assets/de440s.bsp"))
        self.eph = self.enterContext(closing(ephemeris))
        self.ts = load.timescale(builtin=True)
        self.site = wgs84.latlon(36.1627, -86.7816)
        self.track = read(TRACK_DIR / "fixture-track.json", {})[FIXTURE_ID]
        self.launch = {"net": self.track["net"], "precision": "MIN", "statusId": 1}

    def evaluate(self, track, *, fresh=True, fixture=True):
        return evaluate(self.eph, self.ts, self.site, self.launch, track, DEMO_NOW, fresh, fixture)

    def test_only_sourced_current_track_can_produce_a_real_window(self):
        self.assertEqual(self.evaluate(None)["verdict"], "unconfirmed")
        self.assertEqual(self.evaluate(self.track, fixture=False)["verdict"], "unconfirmed")
        self.assertEqual(self.evaluate(self.track, fresh=False)["verdict"], "unconfirmed")
        self.assertEqual(self.evaluate({**self.track, "net": "2026-11-09T23:36:00Z"})["windows"], [])

    def test_simulated_twilight_window_has_time_and_direction(self):
        result = self.evaluate(self.track)
        self.assertEqual(result["verdict"], "possible")
        self.assertEqual(result["windows"][0]["start"]["direction"], "SE")
        self.assertEqual(result["windows"][0]["end"]["time"], "2026-11-09T23:39:50Z")

    def test_daylight_and_sampling_gaps_do_not_produce_windows(self):
        points = validate_points(self.track["points"])
        net = utc(self.track["net"])
        self.assertEqual(windows_for_track(self.eph, self.ts, self.site, net - timedelta(hours=4), points), [])
        self.assertEqual(windows_for_track(self.eph, self.ts, self.site, net, [points[0], points[-1]]), [])
