from datetime import datetime,timedelta,timezone
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from observing_preferences import preferences, validate, in_quiet_hours
from planner import event, assess, station_events
from place_lookup import search
from observatory.notifications.planner_alerts import eligible,record
from conditions import classify
from astronomy import iso

NOW=datetime(2026,11,12,18,tzinfo=timezone.utc)

class ExpandedPlanningTests(unittest.TestCase):
    def setUp(self):
        self.settings={'weather':True,'alerts':True,'observing':{'alert_types':['station','meteor','launch']}}
        self.place={'id':'test','lat':36.,'lon':-86.,'elevation':0}
        self.snapshot={'settings':self.settings,'place':self.place}
        self.forecast={'key':'36.00,-86.00','fetched':iso(NOW),'data':{'hourly':{
            'time':[iso(NOW+timedelta(hours=i)) for i in range(10)],
            **{key:[value]*10 for key,value in [('cloud_cover',20),('cloud_cover_low',10),('cloud_cover_mid',5),
                ('cloud_cover_high',10),('visibility',20000),('precipitation',0),('weather_code',1),('wind_speed_10m',5)]}}}}
        self.row=event('meteor','Test shower',iso(NOW+timedelta(minutes=10)),iso(NOW+timedelta(hours=2)),
            {'time':iso(NOW+timedelta(minutes=30)),'azimuth':90,'altitude':50,'direction':'E'},valid_until=iso(NOW+timedelta(hours=2)))
    def assessed(self,row=None,forecast=None,now=NOW):
        return assess([row or self.row],self.snapshot,forecast or self.forecast,now,iso(NOW))
    def test_geometric_station_pass_remains_inspectable(self):
        station={'name':'Tiangong','source_id':48274,'id':'pass-1',
                 'start':iso(NOW+timedelta(minutes=10)), 'end':iso(NOW+timedelta(minutes=20)),
                 'peak':iso(NOW+timedelta(minutes=15)), 'culmination':{'el':4.5,'az':222,'direction':'SW'},'windows':[]}
        rows=station_events({'events':[station]})
        self.assertEqual(rows[0]['visibility'],'unconfirmed')
        self.assertEqual(rows[0]['look']['el'],4.5)
        self.assertIsNone(self.assessed(rows[0])[1])

    def test_known_geometry_gets_weather_and_transparent_score(self):
        rows,best=self.assessed()
        self.assertEqual(best['conditions']['label'],'Favourable')
        self.assertEqual(round(sum(best['score_parts'].values()),1),best['score'])
    def test_short_imminent_pass_beats_all_evening_planet(self):
        station=event('station','ISS',iso(NOW+timedelta(minutes=10)),iso(NOW+timedelta(minutes=15)),{'time':iso(NOW+timedelta(minutes=12)),'el':30,'az':90,'direction':'E'})
        planet=event('planet','Saturn',iso(NOW-timedelta(minutes=10)),iso(NOW+timedelta(hours=5)),{'time':iso(NOW+timedelta(hours=1)),'el':55,'az':180,'direction':'S'})
        _,best=assess([station,planet],self.snapshot,self.forecast,NOW,iso(NOW))
        self.assertEqual(best['name'],'ISS')

    def test_unconfirmed_launch_and_stale_geometry_cannot_be_featured(self):
        for status in ['unconfirmed','stale']:
            row={**self.row,'kind':'launch','visibility':status}
            rows,best=self.assessed(row)
            self.assertEqual(len(rows),1);self.assertIsNone(best)
        self.assertIsNone(self.assessed({**self.row,'valid_until':iso(NOW-timedelta(seconds=1))})[1])
    def test_poor_weather_stays_inspectable(self):
        f=json.loads(json.dumps(self.forecast));f['data']['hourly']['cloud_cover']=[100]*10
        rows,best=self.assessed(forecast=f)
        self.assertEqual(rows[0]['conditions']['label'],'Poor');self.assertIsNone(best)
    def test_long_window_assesses_later_weather(self):
        f=json.loads(json.dumps(self.forecast));f['data']['hourly']['cloud_cover'][5]=100
        row={**self.row,'end':iso(NOW+timedelta(hours=6))}
        self.assertEqual(self.assessed(row,f)[0][0]['conditions']['label'],'Poor')
    def test_other_locations_forecast_is_not_reused(self):
        f={**self.forecast,'key':'0.00,0.00'}
        self.assertEqual(self.assessed(forecast=f)[0][0]['conditions']['label'],'Uncertain')
    def test_alerts_respect_master_type_weather_and_overlap_dedup(self):
        row=self.assessed()[0][0]
        self.assertTrue(eligible(row,self.settings,NOW,[],'test'))
        self.assertFalse(eligible(row,{**self.settings,'alerts':False},NOW,[],'test'))
        self.assertFalse(eligible(row,self.settings,NOW,[record(row,'test')],'test'))
        shifted={**row,'start':iso(NOW+timedelta(minutes=11))}
        self.assertFalse(eligible(shifted,self.settings,NOW,[record(row,'test')],'test'))
    def test_any_weather_is_explicit_and_never_allows_unknown_visibility(self):
        row=self.assessed()[0][0];row['conditions']['label']='Poor'
        self.assertFalse(eligible(row,self.settings,NOW,[],'test'))
        settings={**self.settings,'observing':{**self.settings['observing'],'alert_conditions':'Any'}}
        self.assertTrue(eligible(row,settings,NOW,[],'test'))
        row['visibility']='unconfirmed'
        self.assertFalse(eligible(row,settings,NOW,[],'test'))
    def test_quiet_hours_cross_midnight_in_system_timezone(self):
        before=os.environ.get('TZ')
        try:
            os.environ['TZ']='America/Chicago';time.tzset()
            settings={'observing':{'quiet_enabled':True,'quiet_start':'22:00','quiet_end':'07:00'}}
            self.assertTrue(in_quiet_hours(datetime(2026,11,13,5,tzinfo=timezone.utc),settings))
            self.assertFalse(in_quiet_hours(NOW,settings))
        finally:
            if before is None:os.environ.pop('TZ',None)
            else:os.environ['TZ']=before
            time.tzset()
    def test_preferences_reject_duplicates_and_invalid_consent(self):
        for bad in [{'quiet_enabled':'true'},{'quiet_start':'29:99'},{'alert_lead_minutes':0},
                    {'watchlist':[{'number':1,'name':'one'},{'number':1,'name':'duplicate'}]}]:
            with self.assertRaises(ValueError):validate(bad)
        self.assertEqual(preferences({})['alert_types'],['station'])
    def test_custom_watchlist_fixture_respects_selection_without_network(self):
        from observatory.satellites.watchlist import prepare
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);state=root/'observer';state.mkdir()
            (state/'settings.json').write_text(json.dumps({'observing':{'watchlist':[{'number':999999,'name':'Unknown test object'}]}}))
            with patch('observatory.satellites.watchlist.get_json',side_effect=AssertionError('No fixture network')):
                prepare(root/'result.json',root/'cache',True,state)
            data=json.loads((root/'result.json').read_text())
            self.assertEqual(data['targets'],[{'name':'Unknown test object','number':999999,'usable':False}])
            self.assertEqual(data['windows'],[])
    def test_meteor_activity_dates_and_catalogue_cover_2027(self):
        from observatory.meteors.meteors import CATALOG
        self.assertGreaterEqual(CATALOG['until'],'2027-12-27T00:00:00Z')
        for row in CATALOG['showers']:
            self.assertLessEqual(row['activeStart'],row['peak'][:10])
            self.assertGreaterEqual(row['activeEnd'],row['peak'][:10])
        self.assertTrue(any(row['name']=='Perseids' and row['peak'].startswith('2027-08') for row in CATALOG['showers']))
    def test_comet_refresh_requires_complete_positions_and_qualified_magnitude(self):
        from observatory.comets.refresh_catalog import track,magnitude
        with self.assertRaises(ValueError):track({'result':'Ambiguous comet'},NOW,NOW+timedelta(days=1))
        with self.assertRaises(ValueError):magnitude({'signature':{'version':'1.5'},'objects':[]},NOW)
        root=Path(__file__).resolve().parents[1]
        catalog=json.loads((root/'observatory/comets/catalog.json').read_text())
        self.assertEqual(catalog['until'],'2026-12-12T00:00:00Z')
        self.assertTrue(all(len(row['positions'])==397 for row in catalog['targets']))

    def test_lookup_encodes_only_supplied_query_and_validates_response(self):
        seen=[]
        def fetch(url,**kwargs):
            seen.append(url)
            return {'results':[{'name':'Example','latitude':36,'longitude':-86,'country':'US'},
                               {'name':'Invalid','latitude':float('nan'),'longitude':0}]}
        result=search('Example, US',fetch)
        self.assertEqual(len(result),1)
        self.assertIn('name=Example%2C+US',seen[0]);self.assertNotIn('latitude=',seen[0])
    def test_preferences_command_does_not_retimestamp_snapshot(self):
        import subprocess
        root=Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            state=Path(folder);(state/'snapshot.json').write_text(json.dumps({'generated':iso(NOW),'settings':{}}))
            run=subprocess.run([sys.executable,str(root/'worker.py'),'--state',folder,'preferences-stdin'],
                input=json.dumps({'alert_lead_minutes':30,'watchlist':[{'number':20580,'name':'Hubble'}]})+'\n',text=True,capture_output=True)
            self.assertEqual(run.returncode,0,run.stderr)
            self.assertEqual(json.loads((state/'snapshot.json').read_text())['generated'],iso(NOW))
            self.assertEqual(json.loads((state/'settings.json').read_text())['observing']['alert_lead_minutes'],30)

if __name__=='__main__':unittest.main()
