"""Regression checks for the observing companion additions."""
from datetime import timedelta
from unittest import TestCase
from unittest.mock import Mock

from astronomy import utc
from conditions import classify, FIELDS, weather_hours
from observatory.field.stellarium import focus
from observatory.notifications.planner_alerts import eligible
from observatory.planets.jupiter_moons import event_ranges, geometry

NOW = utc('2026-11-28T01:55:00Z')


class ObservingRoadmapTests(TestCase):
    def test_dew_risk_and_backwards_compatible_forecast(self):
        window = {'start': {'time': '2026-11-28T02:06:00Z'}, 'end': {'time': '2026-11-28T02:15:00Z'}}
        raw = {'time': ['2026-11-28T02:00:00Z', '2026-11-28T03:00:00Z'],
               **{k: [0, 0] for k in FIELDS}, 'visibility': [16000, 16000]}

        def result():
            hours = weather_hours({'hourly': raw})
            return classify(window, hours, NOW.isoformat(), NOW, True)

        self.assertEqual(result()['label'], 'Favourable')
        self.assertIsNone(result()['dewRisk'])
        raw.update(temperature_2m=[4, 3], dew_point_2m=[2.5, 0], relative_humidity_2m=[82, 75])
        self.assertEqual(result()['dewRisk'], 'High')
        raw['dew_point_2m'] = [-9, None]
        self.assertIsNone(result()['dewRisk'])

    def test_clear_and_dark_requires_weather_darkness_and_existing_deduplication(self):
        row = {'kind': 'station', 'object_id': '25544', 'recommended': True,
               'start': '2026-11-28T02:06:00Z', 'end': '2026-11-28T02:15:00Z',
               'look': {'time': '2026-11-28T02:08:00Z', 'el': 45}, 'visibility': 'possible',
               'conditions': {'label': 'Favourable'}}
        settings = {'alerts': True, 'weather': True, 'observing': {'clear_sky_only': True, 'alert_conditions': 'Any'}}
        dark = Mock(return_value=True)
        self.assertTrue(eligible(row, settings, NOW, [], 'home', dark=dark))
        dark.assert_called_once_with(utc(row['start']), utc(row['look']['time']))
        self.assertFalse(eligible(row, settings, NOW, [], 'home', dark=lambda *_: False))
        self.assertFalse(eligible(row, settings, NOW, [row | {'location': 'home'}], 'home', dark=dark))
        row['conditions']['label'] = 'Uncertain'
        self.assertFalse(eligible(row, settings, NOW, [], 'home', dark=dark))
        self.assertTrue(eligible(row, settings | {'observing': {'alert_conditions': 'Any'}}, NOW, [], 'home'))

    def test_stellarium_posts_only_target_to_loopback(self):
        connect = Mock()
        server = connect.return_value
        server.getresponse.return_value.status = 200
        server.getresponse.return_value.read.return_value = b'true'
        self.assertEqual(focus('M110', connect), 'Stellarium centred on M110.')
        connect.assert_called_once_with('127.0.0.1', 8090, timeout=3)
        self.assertEqual(server.request.call_args.args[:3], ('POST', '/api/main/focus', 'target=M110&mode=center'))
        server.close.assert_called_once()
        server.getresponse.return_value.read.return_value = b'false'
        with self.assertRaisesRegex(ValueError, 'recognise'):
            focus('M110', connect)

    def test_moon_search_refines_boundaries_and_retains_clipping(self):
        def sample(when):
            minutes = (when - NOW).total_seconds() / 60
            return (minutes < 20, 24 <= minutes < 40)

        twilight = NOW + timedelta(hours=1)
        first, second = list(event_ranges(NOW, twilight, sample))
        self.assertTrue(first[3])
        self.assertFalse(second[3])
        self.assertLess(abs((first[2]-NOW).total_seconds()-1200), 60)
        self.assertLess(abs((second[1]-NOW).total_seconds()-1440), 60)
        # Known PyMeeus example shows Io well outside the limb at this epoch.
        self.assertFalse(geometry(utc('1992-12-16T00:00:00Z'))[0])
