from copy import deepcopy
from datetime import datetime,timedelta,timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from zoneinfo import ZoneInfoNotFoundError
from astronomy import iso,utc
from worker import write,read
from observatory.offline import offline as m
NOW=datetime(2026,11,14,18,tzinfo=timezone.utc)

class OfflineCardsTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.path=Path(self.tmp.name)
        self.request={'source':'sample','zone':'America/Chicago','night':'2026-11-14'}
        self.deck=m.prepare(self.path,self.request,NOW)
        self.iss=next(r for r in self.deck['rows'] if r['name']=='ISS')
    def save_iss(self,**extra):return m.save(self.path,{**self.request,'ids':[self.iss['id']],**extra},NOW)
    def test_noon_to_noon_handles_dst_and_invalid_inputs(self):
        a,b=m.night_window('2026-10-31','America/Chicago');self.assertEqual(b-a,timedelta(hours=25))
        a,b=m.night_window('2026-03-07','America/Chicago');self.assertEqual(b-a,timedelta(hours=23))
        for d in ('2026-02-30','../bad','2026-1-1'):
            with self.assertRaises(ValueError):m.night_window(d,'UTC')
        with self.assertRaises(ZoneInfoNotFoundError):m.night_window('2026-11-14','Invented/Place')
    def test_default_night_includes_following_morning(self):
        other=self.path/'early';other.mkdir()
        now=datetime(2026,11,14,10,tzinfo=timezone.utc)
        d=m.prepare(other,{'zone':'America/Chicago'},now)
        self.assertEqual(d['night'],'2026-11-13')
    def test_equipment_and_peak_direction_are_saved(self):
        self.assertIn('Naked eye',self.iss['equipment']);self.assertTrue(self.iss['lookUsable'])
        d=m.view(self.deck,NOW);row=next(r for r in d['rows'] if r['name']=='ISS')
        self.assertIn('140.0°',row['directionText']);self.assertIn('CST',row['when'])
        solar=next(r for r in d['rows'] if r['solar']);self.assertFalse(solar['equipment']);self.assertIn('Solar safety',solar['equipmentNote'])
    def test_clip_long_window_does_not_extrapolate_direction(self):
        raw=deepcopy(self.iss);raw['start']='2026-11-13T18:00Z';raw['end']='2026-11-16T18:00Z';raw['look']['time']='2026-11-13T19:00Z'
        p=self.path/'planner.json';write(p,{'generated':iso(NOW),'events':[raw]})
        d=m.prepare(self.path,{**self.request,'source':'live'},NOW,p);r=d['rows'][0]
        self.assertEqual(r['segmentStart'],d['windowStart']);self.assertEqual(r['segmentEnd'],d['windowEnd'])
        self.assertFalse(r['lookUsable']);self.assertIn('unavailable',m.direction(r,d['zone']))
    def test_wrong_night_empty_without_new_predictions(self):
        d=m.prepare(self.path,{**self.request,'night':'2027-01-01'},NOW)
        self.assertEqual(d['rows'],[])
    def test_immutable_saved_snapshot_reopens_without_live_source(self):
        guide,deck=self.save_iss();folder=self.path/'guides'/guide
        before={p.name:p.read_bytes() for p in folder.iterdir()}
        with patch.object(m,'source_data',side_effect=AssertionError('Offline open must not read planner')),patch.object(m,'prepare',side_effect=AssertionError('No regeneration')):
            m.run(self.path,'open',{'guide':guide},NOW+timedelta(hours=3))
        self.assertEqual(before,{p.name:p.read_bytes() for p in folder.iterdir()})
        v=read(self.path/'view.json',{});self.assertEqual(v['mode'],'saved');self.assertIn('Ended',v['deck']['rows'][0]['status'])
    def test_age_end_clock_mismatch_and_source_flags(self):
        r=deepcopy(self.iss);r['segmentEnd']=iso(NOW+timedelta(hours=12))
        self.assertIn('not a live',m.row_status(r,NOW));self.assertIn('aged',m.row_status(r,NOW+timedelta(hours=2)))
        self.assertIn('Clock mismatch',m.row_status(r,NOW-timedelta(seconds=1)))
        r['staleAtCapture']=True;self.assertIn('Stale when',m.row_status(r,NOW))
        r['staleAtCapture']=False;r['sourceIssues']=True;self.assertIn('Incomplete',m.row_status(r,NOW))
        self.assertIn('Ended',m.row_status(r,NOW+timedelta(hours=13)))
    def test_weather_age_is_separate_and_unknown_stays_unknown(self):
        self.assertIn('Saved forecast',m.weather_status(self.iss,NOW))
        self.assertIn('stale',m.weather_status(self.iss,NOW+timedelta(hours=6)))
        self.assertIn('clock mismatch',m.weather_status(self.iss,NOW-timedelta(minutes=1)))
        r=deepcopy(self.iss);r['conditions']['fetched']=None;r['weatherExpires']=''
        self.assertIn('unknown',m.weather_status(r,NOW))
    def test_capture_stale_requires_explicit_inspection_choice(self):
        stale=next(r for r in self.deck['rows'] if r['staleAtCapture'])
        payload={**self.request,'ids':[stale['id']]}
        with self.assertRaises(ValueError):m.save(self.path,payload,NOW)
        guide,d=m.save(self.path,{**payload,'includeStale':True},NOW)
        self.assertTrue(d['rows'][0]['staleAtCapture']);self.assertIn('Stale when',m.view(d,NOW)['rows'][0]['status'])
    def test_source_expiry_shortens_two_hour_limit(self):
        raw=deepcopy(self.iss);raw['valid_until']=iso(NOW+timedelta(minutes=10))
        p=self.path/'planner.json';write(p,{'generated':iso(NOW),'events':[raw]})
        r=m.prepare(self.path,{**self.request,'source':'live'},NOW,p)['rows'][0]
        self.assertEqual(r['recheckAt'],raw['valid_until'])
    def test_private_location_fields_not_copied(self):
        raw=deepcopy(self.iss);raw.update({'coordinates':[11.123456,22.654321],'place_name':'PRIVATE TEST PLACE'})
        p=self.path/'planner.json';write(p,{'generated':iso(NOW),'events':[raw],'location_id':'PRIVATE TEST ID','place':{'name':'PRIVATE TEST PLACE'}});before=p.read_bytes()
        with patch('urllib.request.urlopen',side_effect=AssertionError('No network')):
            d=m.prepare(self.path,{**self.request,'source':'live'},NOW,p)
        d['savedAt']=iso(NOW);out=json.dumps(d)+m.render_html(d,NOW)
        self.assertNotIn('PRIVATE TEST',out);self.assertNotIn('11.123456',out);self.assertEqual(p.read_bytes(),before)
    def test_html_self_contained_escaped_and_printable(self):
        guide,d=self.save_iss();d['rows'][0]['name']='</script><img src="https://evil.invalid" onerror="boom">'
        out=m.render_html(d,NOW)
        self.assertNotIn('<img',out);self.assertIn('&lt;/script&gt;',out);self.assertEqual(out.count('<script>'),1)
        self.assertIn("default-src 'none'",out);self.assertIn('@media print',out);self.assertIn('<noscript>',out)
        self.assertIn('data-recheck=',out);self.assertIn('setInterval(refresh,30000)',out)
        self.assertNotIn('fetch(',out);self.assertNotIn('<link',out);self.assertNotIn('<iframe',out)
    def test_no_overwrite_and_saved_files_private(self):
        a,d=self.save_iss();b,_=self.save_iss();self.assertNotEqual(a,b)
        for name in ('deck.json','guide.html'):self.assertEqual((self.path/'guides'/a/name).stat().st_mode&0o777,0o600)
        self.assertEqual(len(m.saved_list(self.path)),2)
    def test_unknown_selection_limit_unsupported_launch_and_traversal(self):
        for ids in ([],[self.iss['id']]*2,['x']*51,['invented']):
            with self.assertRaises(ValueError):m.save(self.path,{**self.request,'ids':ids},NOW)
        launch=next(r for r in self.deck['rows'] if r['kind']=='launch')
        with self.assertRaises(ValueError):m.save(self.path,{**self.request,'ids':[launch['id']]},NOW)
        for guide in ('../planner.json','/etc/passwd','missing'):
            with self.assertRaises(ValueError):m.load_saved(self.path,guide)
    def test_corrupt_saved_guide_is_retained(self):
        guide,_=self.save_iss();p=self.path/'guides'/guide/'deck.json';p.write_text('{broken')
        with self.assertRaises(ValueError):m.load_saved(self.path,guide)
        self.assertEqual(p.read_text(),'{broken');self.assertEqual(m.saved_list(self.path),[])

    def test_aged_look_point_is_stale_when_captured(self):
        raw=deepcopy(self.iss);raw['look']['time']=iso(NOW-timedelta(minutes=6))
        p=self.path/'planner.json';write(p,{'generated':iso(NOW),'events':[raw]})
        row=m.prepare(self.path,{**self.request,'source':'live'},NOW,p)['rows'][0]
        self.assertTrue(row['staleAtCapture'])
