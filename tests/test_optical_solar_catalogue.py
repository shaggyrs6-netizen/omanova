from datetime import timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase

from astronomy import iso, utc
from conditions import FIELDS, optical_context, weather_hours
from observatory.aurora.solar_wind import FEEDS, latest_active, sample
from observatory.field.field import CAT
from observatory.my_night.plan import TARGETS


class ObservingContextTests(TestCase):
    def test_optical_estimates_require_inputs_and_old_forecasts_parse(self):
        time = '2026-11-28T12:00:00Z'
        raw = {'time': [time], **{key: [0] for key in FIELDS},
               'wind_speed_10m': [8], 'cloud_cover': [8], 'visibility': [20000]}
        old = weather_hours({'hourly': raw})[utc(time)]
        self.assertIsNone(optical_context(old)['seeing'])
        self.assertIsNone(optical_context(old)['transparency'])
        raw.update(wind_speed_850hPa=[24], wind_speed_200hPa=[60], relative_humidity_2m=[62])
        quality = optical_context(weather_hours({'hourly': raw})[utc(time)])
        self.assertEqual(quality['seeing'], 'Lower turbulence risk')
        self.assertEqual(quality['transparency'], 'Clear-air potential')
        raw.update(wind_speed_200hPa=[145], cloud_cover=[90])
        quality = optical_context(weather_hours({'hourly': raw})[utc(time)])
        self.assertEqual(quality['seeing'], 'Higher turbulence risk')
        self.assertEqual(quality['transparency'], 'Obscured')

    def test_solar_samples_respect_source_quality_age_and_opt_in(self):
        now = utc('2026-11-28T12:00:00Z')
        block = {'active': True, 'overall_quality': 0, 'source': 'SOLAR1',
                 'proton_speed': 520, 'proton_density': 5.2}
        rows = [
            {**block, 'active': False, 'time_tag': iso(now)},
            {**block, 'overall_quality': 1, 'time_tag': iso(now)},
            {**block, 'time_tag': iso(now + timedelta(minutes=1))},
            {**block, 'time_tag': iso(now - timedelta(minutes=15))},
            {**block, 'time_tag': iso(now - timedelta(minutes=2))},
        ]
        picked = latest_active(rows, FEEDS['plasma'][1], now)
        self.assertEqual(picked['observed'], rows[-1]['time_tag'])
        self.assertEqual(picked['speed'], 520)
        with TemporaryDirectory() as directory:
            state = Path(directory)
            attempts = []

            def fetch(url, **kwargs):
                attempts.append(url)
                return rows

            self.assertEqual(sample(state, 'plasma', now, False, fetch), (None, False))
            self.assertFalse(attempts)
            self.assertEqual(sample(state, 'plasma', now, True, fetch), (picked, False))
            self.assertEqual(sample(state, 'plasma', now + timedelta(minutes=3), True, fetch), (picked, False))
            self.assertEqual(len(attempts), 1)
            self.assertEqual(sample(state, 'plasma', now + timedelta(minutes=20), False, fetch), (None, False))
            self.assertEqual(len(attempts), 1)

    def test_catalogue_ids_are_unique_and_available_to_my_night(self):
        keys = [target['id'] for target in CAT['targets']]
        self.assertEqual(len(keys), len(set(keys)))
        self.assertEqual(sum(key.startswith(('NGC', 'IC')) for key in keys), 149)
        for key in ('M31', 'NGC7000', 'IC5070'):
            self.assertIn(key, TARGETS)
            self.assertGreater(TARGETS[key]['extent'], 0)
