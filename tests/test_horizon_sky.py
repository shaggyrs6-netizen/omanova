"""Regression checks for skyline classification and clearance timing."""
from unittest import TestCase
from datetime import timedelta

from skyfield.api import load, load_file

from astronomy import utc
from observatory.trips.horizon_sky import ROOT, calculate


class HorizonSkyTests(TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ts = load.timescale(builtin=True)
        cls.eph = load_file(str(ROOT / 'assets/de440s.bsp'))
        cls.nashville = {'lat': 36.1627, 'lon': -86.7816, 'elevation': 0,
                         'timezone': 'America/Chicago', 'horizon': []}
        cls.when = utc('2026-12-01T08:15:00Z')

    @classmethod
    def tearDownClass(cls):
        cls.eph.close()

    def test_manual_and_terrain_skyline_and_next_clearance(self):
        selected = calculate(self.eph, self.ts, self.nashville, None, self.when, 'Jupiter')['selected']
        self.assertEqual(selected['status'], 'clear')
        self.assertAlmostEqual(selected['el'], 46, delta=1)
        self.assertAlmostEqual(selected['az'], 110, delta=1)

        place = self.nashville | {'horizon': [{'from': 80, 'to': 142, 'height': 47}]}
        terrain = {'samples': [50] * 720}
        result = calculate(self.eph, self.ts, place, terrain, self.when, 'Jupiter')
        self.assertEqual(result['selected']['status'], 'blocked')
        self.assertEqual(result['selected']['skyline'], 50)
        self.assertTrue(result['nextClear'])
        self.assertIn('CST', result['nextClear'])
        later = calculate(self.eph, self.ts, place, terrain, self.when + timedelta(minutes=35), 'Jupiter')
        self.assertEqual(later['selected']['status'], 'clear')

    def test_below_horizon_objects_stay_selectable(self):
        result = calculate(self.eph, self.ts, self.nashville, None, self.when, 'Sun')
        self.assertEqual(result['selected']['status'], 'below')
        self.assertLess(result['selected']['el'], -20)
        self.assertTrue(result['nextClear'])
        self.assertTrue(any(star['status'] == 'below' for star in result['stars']))
        self.assertTrue(all(star['el'] >= -20 for star in result['stars']))
