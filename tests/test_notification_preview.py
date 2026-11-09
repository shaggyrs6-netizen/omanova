from datetime import timedelta
from pathlib import Path
from subprocess import TimeoutExpired
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import Mock

from observatory.notifications.alerts import decision, sent_record
from observatory.notifications.preview import prepare, scenario_for, send_preview
from worker import apply_settings, check_station_alerts, read, settings_at


class NotificationPreviewTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = TemporaryDirectory()
        cls.addClassCleanup(temp.cleanup)
        cls.state = Path(temp.name)
        prepare(cls.state)
        cls.samples = read(cls.state / "samples.json", {})

    def test_opt_in_and_lead_window(self):
        for sample in self.samples.values():
            event, window, now = scenario_for(sample, "favourable")
            self.assertIn("off", decision(event, window, now, False, []))
            self.assertIn("Waiting", decision(event, window, now - timedelta(seconds=1), True, []))
            self.assertIsNone(decision(event, window, now, True, []))
            self.assertIn("already started", decision(event, window, now + timedelta(minutes=15), True, []))

    def test_bad_conditions_and_expired_pass_are_suppressed(self):
        for scenario, reason in (("poor", "forecast is poor"), ("missing", "missing or expired"),
                                 ("stale", "elements are stale"), ("ended", "window has ended")):
            event, window, now = scenario_for(self.samples["25544"], scenario)
            self.assertIn(reason, decision(event, window, now, True, []))

    def test_same_pass_after_orbit_recalculation_is_deduplicated(self):
        event, window, now = scenario_for(self.samples["25544"], "favourable")
        shifted = {**event, "start": window["start"]["time"]}
        self.assertIn("already sent", decision(shifted, window, now, True, [sent_record(event)]))

    def test_delivery_and_retry_in_isolated_state(self):
        with TemporaryDirectory() as temp:
            state = Path(temp)
            from worker import write
            write(state / "samples.json", self.samples)
            failed = Mock(side_effect=TimeoutExpired("notify-send", 5))
            self.assertIn("eligible for a retry", send_preview(state, 25544, "favourable", True, failed))
            sender = Mock()
            self.assertIn("ISS", send_preview(state, 25544, "favourable", True, sender))
            self.assertIn("already sent", send_preview(state, 25544, "favourable", True, sender))
            self.assertIn("Tiangong", send_preview(state, 48274, "favourable", True, sender))
            self.assertEqual(sender.call_count, 2)
            self.assertIn("[Preview] Tiangong in 15 minutes", sender.call_args.args[0])

    def test_live_worker_respects_opt_in_and_persists_deduplication(self):
        with TemporaryDirectory() as temp:
            state = Path(temp)
            settings = settings_at(state)
            self.assertIs(settings["alerts"], False)
            event, window, now = scenario_for(self.samples["25544"], "favourable")
            event["windows"] = [window]
            snapshot = {"demo": False, "settings": settings, "events": [event]}
            sender = Mock(return_value=True)
            check_station_alerts(state, snapshot, now, sender)
            sender.assert_not_called()
            apply_settings(settings, "alerts", ("on",))
            check_station_alerts(state, {**snapshot, "demo": True}, now, sender)
            sender.assert_not_called()
            check_station_alerts(state, snapshot, now + timedelta(seconds=27), sender)
            check_station_alerts(state, snapshot, now + timedelta(seconds=50), sender)
            sender.assert_called_once_with(event, window, 15)
            self.assertEqual(read(state / "station-alerts.json", []), [sent_record(event)])
