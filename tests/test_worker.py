import fcntl
import json
from datetime import timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import call, patch
from urllib.error import HTTPError

from astronomy import iso, utc
from conditions import FIELDS, classify, opportunities, weather_hours
from worker import DEMO_NOW, OPT_INS, apply_settings, build_snapshot, main, settings_at, update_source, watch, write


def example_weather():
    return {"hourly": {
        "time": ["2026-11-09T12:00", "2026-11-09T23:00", "2026-11-10T00:00"],
        **{key: [0, 0, 0] for key in FIELDS},
        "cloud_cover": [100, 20, 28], "visibility": [3000, 20000, 20000],
    }}


class WorkerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name)
        self.window = {"start": {"time": "2026-11-09T23:41:19Z"},
                       "end": {"time": "2026-11-09T23:44:23Z"}, "peak": {"el": 18.2}}

    def test_manual_setup_and_fixture_make_no_network_calls(self):
        settings = settings_at(self.state)
        self.assertFalse(settings["weather"])
        self.assertFalse(settings["online"])
        apply_settings(settings, "save", ("Nashville", "36.1627", "-86.7816", ""))
        settings.update(online=True, weather=True)
        write(self.state / "settings.json", settings)
        with patch("worker.get_json", side_effect=AssertionError("Unexpected network request")):
            snapshot = build_snapshot(self.state, fixture=True)
        self.assertEqual(snapshot["place"]["name"], "Nashville")
        self.assertEqual(snapshot["candidates"][0]["conditions"], "Uncertain")
        self.assertEqual(json.loads((self.state / "snapshot.json").read_text()), snapshot)

    def test_opt_ins_require_json_true(self):
        for value in ("true", "false", 1, None, False, True):
            with self.subTest(value=value):
                write(self.state / "settings.json", dict.fromkeys(OPT_INS, value))
                settings = settings_at(self.state)
                self.assertTrue(all(settings[key] is (value is True) for key in OPT_INS))

    def test_watch_recovers_after_transient_refresh_errors(self):
        results = [OSError("temporary failure"), ValueError("invalid data"),
                   {"status": "Predictions ready"}, OSError("temporary failure")]
        with patch("worker.build_snapshot", side_effect=results) as refresh, patch(
            "worker.time.sleep", side_effect=[None, None, None, KeyboardInterrupt]
        ) as sleep, patch("builtins.print"):
            with self.assertRaises(KeyboardInterrupt):
                watch(self.state, fixture=True)
        self.assertEqual(refresh.call_args_list, [call(self.state, True)] * 4)
        self.assertEqual(sleep.call_args_list, [call(15), call(30), call(60), call(15)])

    def test_second_worker_does_not_watch_the_same_state(self):
        with (self.state / "watch.lock").open("a") as running:
            fcntl.flock(running, fcntl.LOCK_EX)
            with patch("sys.argv", ["worker.py", "--state", str(self.state), "--fixture", "watch"]), patch(
                "worker.watch"
            ) as watch_loop, patch("builtins.print"):
                self.assertEqual(main(), 75)
                watch_loop.assert_not_called()

    def test_opted_in_weather_only_sends_rounded_coords(self):
        settings = settings_at(self.state)
        apply_settings(settings, "save", ("Nashville", "36.1627", "-86.7816", ""))
        settings["online"] = True
        write(self.state / "settings.json", settings)
        rows = json.loads((Path(__file__).parent / "fixtures/stations.json").read_text())
        with patch("worker.get_json", return_value=rows) as fetch:
            build_snapshot(self.state)
        self.assertEqual(fetch.call_count, 1)
        self.assertNotIn("latitude", fetch.call_args.args[0])
        settings["weather"] = True
        write(self.state / "settings.json", settings)
        with patch("worker.get_json", return_value=example_weather()) as fetch:
            build_snapshot(self.state)
        self.assertEqual(fetch.call_count, 1)
        url = fetch.call_args.args[0]
        self.assertIn("latitude=36.16&longitude=-86.78", url)
        self.assertNotIn("36.1627", url)

    def test_weather_uses_event_hours_and_crosses_midnight(self):
        hours = weather_hours(example_weather())
        fetched = iso(DEMO_NOW)
        result = classify(self.window, hours, fetched, DEMO_NOW, True)
        self.assertEqual(result["label"], "Favourable")
        self.assertEqual([row["cloud_cover"] for row in result["hours"]], [20, 28])
        hours[utc("2026-11-10T00:00Z")]["cloud_cover"] = 99
        self.assertEqual(classify(self.window, hours, fetched, DEMO_NOW, True)["label"], "Poor")
        hours.pop(utc("2026-11-10T00:00Z"))
        self.assertEqual(classify(self.window, hours, fetched, DEMO_NOW, True)["label"], "Uncertain")
        self.assertEqual(classify(self.window, hours, fetched, DEMO_NOW + timedelta(hours=7), True)["hours"], [])

    def test_poor_and_stale_passes_stay_off_bar(self):
        event = {"id": "one", "confidence": "Provisional", "windows": [self.window]}
        for label, confidence, eligible in (("Poor", "Provisional", False),
                                             ("Favourable", "Stale orbit", False),
                                             ("Uncertain", "Provisional", True)):
            self.window["conditions"] = {"label": label}
            event["confidence"] = confidence
            self.assertEqual(bool(opportunities([event], DEMO_NOW)), eligible)

    def test_provider_throttle_keeps_last_good_and_does_not_retry(self):
        def fail():
            raise HTTPError("https://example.invalid", 429, "", {"Retry-After": "14400"}, None)
        orbital = {"data": ["retained"]}
        weather = {"data": ["retained"]}
        update_source(orbital, DEMO_NOW, timedelta(hours=2), fail, lambda _: None, stop_on_http=True)
        self.assertTrue(orbital["blocked"])
        update_source(weather, DEMO_NOW, timedelta(hours=3), fail, lambda _: None)
        self.assertEqual(weather["next"], iso(DEMO_NOW + timedelta(hours=4)))
        for cache in (orbital, weather):
            update_source(cache, DEMO_NOW + timedelta(hours=1), timedelta(hours=1),
                          lambda: self.fail("Unexpected retry"), lambda _: None)
            self.assertEqual(cache["data"], ["retained"])

    def test_temporary_location_preserves_saved_profile_and_rejects_bad_input(self):
        settings = settings_at(self.state)
        apply_settings(settings, "save", ("Home", "36", "-86", "0"))
        home = settings["active"]
        apply_settings(settings, "temporary", ("Trip", "-33", "151", "2"))
        self.assertEqual(settings["active"], home)
        self.assertEqual(len(settings["profiles"]), 1)
        with self.assertRaises(ValueError):
            apply_settings(settings, "save", ("Bad", "nan", "-86", "0"))
        apply_settings(settings, "use", (home,))
        self.assertIsNone(settings["temporary"])
