from copy import deepcopy
from datetime import datetime,timedelta,timezone
from pathlib import Path
from unittest.mock import patch
import json,tempfile,unittest
from appearance import save as appearance
from worker import write,read
from astronomy import iso
from observatory.equipment.equipment import profile,fixtures
from observing_context import trip_signature,trip_events
from observatory.trips.trips import validate_config,compare
from observatory.field.field import finder,sites,distance
NOW=datetime(2026,11,14,18,tzinfo=timezone.utc)
class CompletionTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.state=Path(self.tmp.name)
 def config(self):
  return validate_config({'home':{'name':'PRIVATE HOME','lat':36.1627,'lon':-86.7816,'elevation':0,'timezone':'America/Chicago','horizon':[]},'destination':{'name':'PRIVATE DESTINATION','lat':51.5074,'lon':-.1278,'elevation':0,'timezone':'Europe/London','horizon':[]},'start':'2026-11-14','end':'2026-11-14','weather':False})
 def test_display_mode_persists_without_losing_theme_or_data(self):
  (self.state/'settings.json').write_text('private observing settings')
  appearance(self.state,'desktop','red');appearance(self.state,'observatory')
  self.assertEqual(read(self.state/'appearance.json',{})['observing'],'red')
  appearance(self.state,'desktop','normal');self.assertNotIn('observing',read(self.state/'appearance.json',{}))
  self.assertEqual((self.state/'settings.json').read_text(),'private observing settings')
 def test_equipment_values_optional_validated_and_preserved(self):
  p=profile({'apertureMm':100,'fieldOfViewDeg':2,'binocularMagnification':10,'cameraMode':'tracked'})
  self.assertEqual(p['gear'],['eye']);self.assertEqual(p['apertureMm'],100)
  for key,v in [('apertureMm',0),('apertureMm',float('nan')),('fieldOfViewDeg',181),('binocularMagnification',True),('cameraMode','magic')]:
   with self.assertRaises(ValueError):profile({key:v})
 def test_straight_line_distance_and_destination_catalogue(self):
  self.assertEqual(distance(0,0,0,0),0)
  self.assertAlmostEqual(distance(0,0,0,1),111.195,places=2)
  with patch('socket.socket',side_effect=AssertionError('No network')):r=sites(fixture=True,now=NOW)
  self.assertEqual(len(r['rows']),12);self.assertEqual(r['rows'],sorted(r['rows'],key=lambda x:x['distanceKm']))
  self.assertTrue(all(x['source'].startswith('https://') and x['access'] and x['checked'] for x in r['rows']))
 def test_small_finder_is_geometry_only_and_has_darkness_estimate(self):
  with patch('socket.socket',side_effect=AssertionError('No network')):r=finder({'night':'2026-11-14'},True,NOW)
  self.assertEqual(len(r['rows']),10);self.assertLessEqual(r['darkness']['moonFreeHours'],r['darkness']['darkHours'])
  windows=[w for row in r['rows'] for w in row['windows']];self.assertTrue(windows)
  for w in windows:
   self.assertEqual(w['event']['visibility'],'unconfirmed');self.assertFalse(w['event']['recommended']);self.assertGreaterEqual(w['event']['look']['el'],20)
 def test_saved_horizon_blocks_finder_targets(self):
  p={'name':'public test','lat':36.1627,'lon':-86.7816,'elevation':0,'timezone':'America/Chicago','horizon':[{'name':'wall','from':0,'to':360,'height':90}],'observingHeight':1.7,'useTerrain':False}
  with patch('observatory.field.field.point',return_value=(p,None)):r=finder({'night':'2026-11-14'},True,NOW)
  self.assertFalse(any(row['windows'] for row in r['rows']))
 def test_trip_signature_detects_place_date_height_and_horizon_change(self):
  c=self.config();h=trip_signature(c,self.state)
  for key,value in [('start','2026-11-13'),('home',dict(c['home'],observingHeight=10)),('destination',dict(c['destination'],horizon=[{'name':'tree','from':0,'to':360,'height':40}]))]:
   q=deepcopy(c);q[key]=value;self.assertNotEqual(trip_signature(q,self.state),h)
 def test_trip_exports_use_clipped_windows_timezone_and_no_private_coordinates(self):
  c=self.config();r=compare(c,self.state,NOW,orbit={},schedule={});write(self.state/'trip.json',c);write(self.state/'comparison.json',r)
  with patch('socket.socket',side_effect=AssertionError('No network')):data=trip_events('trip-destination',NOW,self.state)
  self.assertTrue(data['horizonApplied']);self.assertEqual(data['timeZone'],'Europe/London');self.assertTrue(data['events'])
  serialized=json.dumps(data);self.assertNotIn('PRIVATE',serialized);self.assertNotIn('51.5074',serialized)
  self.assertTrue(all(row['displayStart'] and row['timeZone']=='Europe/London' for row in data['events']))
  changed=deepcopy(c);changed['destination']['horizon']=[{'name':'wall','from':0,'to':360,'height':90}];write(self.state/'trip.json',changed)
  with self.assertRaises(ValueError):trip_events('trip-destination',NOW,self.state)
 def test_trip_context_roundtrips_to_calendar_and_immutable_guide(self):
  from observatory.calendar import calendar_export as cal
  from observatory.offline import offline
  c=self.config();write(self.state/'trip.json',c);write(self.state/'comparison.json',compare(c,self.state,NOW,orbit={},schedule={}))
  for name in ('calendar','guides'):(self.state/name).mkdir()
  with patch('observing_context.trip_state',return_value=self.state):
   v=cal.catalogue(self.state/'calendar','trip-destination',NOW)
   selected=next(r for r in v['rows'] if not r['blocked']);out=cal.export(self.state/'calendar',{'source':'trip-destination','ids':[selected['id']],'includeCaution':True},NOW)
   self.assertIn(b'Observing time zone: Europe/London',Path(out['path']).read_bytes().replace(b'\r\n ',b''))
   q=offline.prepare(self.state/'guides',{'source':'trip-destination'},NOW)
   self.assertEqual(q['zone'],'Europe/London');self.assertTrue(q['horizonApplied'])
   row=next(r for r in q['rows'] if not r['unsupported']);guide,d=offline.save(self.state/'guides',{'source':'trip-destination','ids':[row['id']],'displayMode':'red','includeStale':True},NOW)
   with patch('observing_context.trip_events',side_effect=AssertionError('Offline archive must not read trip')):offline.run(self.state/'guides','open',{'guide':guide},NOW+timedelta(hours=3))
   self.assertEqual(d['displayMode'],'red');self.assertNotIn('PRIVATE',json.dumps(d))
 def test_comparison_age_never_becomes_fresh_on_export(self):
  c=self.config();write(self.state/'trip.json',c);write(self.state/'comparison.json',compare(c,self.state,NOW,orbit={},schedule={}))
  d=trip_events('trip-home',NOW+timedelta(hours=3),self.state)
  self.assertTrue(d['events']);self.assertTrue(all(r['visibility']=='stale' for r in d['events']))
 def test_equipment_filter_blocks_exports_but_explicit_disable_restores_selection(self):
  from observatory.calendar import calendar_export as cal
  p=profile({'gear':['telescope'],'sky':'dark'})
  with patch.object(cal,'LIVE_STATE',self.state),patch('observing_context.equipment_profile',return_value=p):
   # Real source fixture isolated from the user's planner.
   raw=fixtures(NOW)[0];write(self.state/'planner.json',{'generated':iso(NOW),'events':[raw]})
   d=cal.catalogue(self.state,'live',NOW,self.state/'planner.json');self.assertTrue(d['rows'][0]['blocked'])
   p['filter']=False;d=cal.catalogue(self.state,'live',NOW,self.state/'planner.json');self.assertFalse(d['rows'][0]['blocked'])
