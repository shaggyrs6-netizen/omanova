from contextlib import closing
from datetime import date,datetime,timedelta,timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zoneinfo import ZoneInfo
import numpy as np
from skyfield.api import load,load_file
from astronomy import utc
from observatory.trips.horizon import altitude,validate,place_key
from observatory.trips.trips import (ROOT,validate_config,validate_place,night_bounds,local_stamp,dual,
                                     geometry,weather_for,station_windows,initialise)

UTC=timezone.utc
HOME={'name':'Sample home','lat':36.1627,'lon':-86.7816,'elevation':0,'timezone':'America/Chicago','horizon':[]}
DEST={'name':'London sample','lat':51.5074,'lon':-.1278,'elevation':10,'timezone':'Europe/London','horizon':[]}
CONFIG={'home':HOME,'destination':DEST,'start':'2026-11-20','end':'2026-11-20','weather':False,'horizonStore':{}}

class TripTests(unittest.TestCase):
    def test_local_nights_handle_dst_independently(self):
        start,end=night_bounds(date(2026,10,31),'America/Chicago')
        self.assertEqual((end-start).total_seconds()/3600,25)
        start,end=night_bounds(date(2026,3,7),'America/Chicago')
        self.assertEqual((end-start).total_seconds()/3600,23)
        start,end=night_bounds(date(2026,10,31),'Europe/London')
        self.assertEqual((end-start).total_seconds()/3600,24)
    def test_same_instant_shows_both_dates_and_offsets(self):
        pair=dual(datetime(2026,11,21,2,tzinfo=UTC),CONFIG)
        self.assertIn('20 Nov',pair['home']);self.assertIn('21 Nov',pair['destination'])
        self.assertIn('UTC-06:00',pair['home']);self.assertIn('UTC+00:00',pair['destination'])
    def test_north_wrapping_sectors_and_overlaps(self):
        sectors=validate([{'name':'North trees','from':330,'to':30,'height':25},
                          {'name':'Roof','from':0,'to':60,'height':40}])
        np.testing.assert_equal(altitude([350,0,20,45,90],sectors),[25,40,40,40,0])
        np.testing.assert_equal(altitude([0,180,359],validate([{'name':'Covered','from':0,'to':360,'height':90}])),[90,90,90])
    def test_invalid_masks_coordinates_dates_and_timezones_rejected(self):
        for sectors in [[{'name':'','from':0,'to':90,'height':20}],
                        [{'name':'bad','from':20,'to':20,'height':20}],
                        [{'name':'bad','from':0,'to':90,'height':float('nan')}]]:
            with self.assertRaises(ValueError):validate(sectors)
        for cfg in [{**CONFIG,'end':'2026-11-19'},{**CONFIG,'end':'2026-12-20'},
                    {**CONFIG,'home':{**HOME,'timezone':'No/SuchZone'}},
                    {**CONFIG,'weather':'true'}, {**CONFIG,'home':{**HOME,'lat':float('nan')}}]:
            with self.assertRaises(ValueError):validate_config(cfg)
        with self.assertRaises(ValueError):validate_place({'name':'Missing','timezone':'UTC'})
    def test_same_point_has_one_horizon(self):
        other={**HOME,'horizon':[{'name':'wall','from':0,'to':360,'height':30}]}
        with self.assertRaises(ValueError):validate_config({**CONFIG,'destination':other})
    def test_no_weather_requests_without_consent_or_outside_horizon(self):
        now=datetime(2026,11,12,tzinfo=UTC)
        with tempfile.TemporaryDirectory() as folder:
            def forbidden(*a,**k):raise AssertionError('No network expected')
            self.assertFalse(weather_for(HOME,now,now+timedelta(days=1),Path(folder),False,now,forbidden)[0])
            self.assertFalse(weather_for(HOME,now+timedelta(days=30),now+timedelta(days=31),Path(folder),True,now,forbidden)[0])
    def test_fixture_initialisation_never_reads_live_locations(self):
        with tempfile.TemporaryDirectory() as folder,patch('observatory.trips.trips.settings_at',side_effect=AssertionError('No live read')):
            initialise(Path(folder),True)
            data=json.loads((Path(folder)/'trip.json').read_text())
            self.assertEqual(data['home']['timezone'],'America/Chicago');self.assertFalse(data['weather'])
    def test_preview_keeps_saved_horizon_and_resets_weather_consent(self):
        with tempfile.TemporaryDirectory() as folder:
            state=Path(folder)
            cfg=validate_config({**CONFIG,'home':{**HOME,'horizon':[{'name':'trees','from':50,'to':120,'height':25}]},'weather':True})
            (state/'trip.json').write_text(json.dumps(cfg))
            initialise(state,False)
            data=json.loads((state/'trip.json').read_text())
            self.assertEqual(data['home']['horizon'][0]['height'],25);self.assertFalse(data['weather'])
    def test_horizon_blocks_real_windows_but_not_astronomical_darkness(self):
        ts=load.timescale(builtin=True);now=datetime(2026,11,12,tzinfo=UTC)
        with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
            clear=geometry(eph,ts,HOME,date(2026,11,20),CONFIG,{},None,now)
            covered={**HOME,'horizon':[{'name':'Test roof','from':0,'to':360,'height':90}]}
            blocked=geometry(eph,ts,covered,date(2026,11,20),{**CONFIG,'home':covered},{},None,now)
        self.assertTrue(any(t['windows'] for t in clear['targets']))
        self.assertTrue(all(not t['windows'] for t in blocked['targets']))
        self.assertTrue(any(t['status']=='Blocked by your horizon' for t in blocked['targets']))
        self.assertEqual(clear['darkHours'],blocked['darkHours'])
        self.assertEqual(clear['moonFreeHours'],blocked['moonFreeHours'])
        for target in clear['targets']:
            for w in target['windows']:
                self.assertLessEqual(w['start']['utc'],w['look']['utc']);self.assertLessEqual(w['look']['utc'],w['end']['utc'])
    def test_repeated_dst_hour_has_distinct_offsets(self):
        first=local_stamp(datetime(2026,11,1,6,30,tzinfo=UTC),'America/Chicago')
        second=local_stamp(datetime(2026,11,1,7,30,tzinfo=UTC),'America/Chicago')
        self.assertIn('01:30',first);self.assertIn('01:30',second)
        self.assertIn('UTC-05:00',first);self.assertIn('UTC-06:00',second)
    def test_weather_opt_in_rounds_locations_and_caches(self):
        from conditions import FIELDS
        now=datetime(2026,11,12,12,tzinfo=UTC);calls=[]
        def fetch(url):
            calls.append(url)
            return {'hourly':{'time':['2026-11-12T12:00:00Z'],**{k:[0] for k in FIELDS}}}
        with tempfile.TemporaryDirectory() as folder:
            for _ in range(2):weather_for(HOME,now,now+timedelta(hours=1),Path(folder),True,now,fetch)
        self.assertEqual(len(calls),1)
        self.assertIn('latitude=36.16',calls[0]);self.assertIn('longitude=-86.78',calls[0])
        self.assertNotIn('36.1627',calls[0])
    def test_cached_station_windows_are_clipped_by_horizon(self):
        rows=json.loads((ROOT/'tests/fixtures/stations.json').read_text())
        ts=load.timescale(builtin=True)
        start,end=night_bounds(date(2026,11,9),HOME['timezone'])
        covered={**HOME,'horizon':[{'name':'roof','from':0,'to':360,'height':90}]}
        with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
            clear,_=station_windows(eph,ts,HOME,start,end,CONFIG,{'data':rows})
            blocked,_=station_windows(eph,ts,covered,start,end,CONFIG,{'data':rows})
        self.assertTrue(clear);self.assertEqual(blocked,[])
        for w in clear:
            self.assertLess(w['start']['utc'],w['end']['utc'])
            self.assertIn('UTC-06:00',w['look']['home'])

    def test_far_future_station_data_is_withheld(self):
        rows=json.loads((ROOT/'tests/fixtures/stations.json').read_text())
        ts=load.timescale(builtin=True)
        with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
            windows,note=station_windows(eph,ts,HOME,utc('2027-01-01T00:00:00Z'),utc('2027-01-02T00:00:00Z'),CONFIG,{'data':rows})
        self.assertEqual(windows,[]);self.assertIn('recheck',note.lower())

if __name__=='__main__':unittest.main()
