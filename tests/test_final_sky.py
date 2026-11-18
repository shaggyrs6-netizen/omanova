"""Geometry fixtures include an independent ECEF ray/ellipsoid transit construction.

These validate numerical geometry, not the accuracy of a real public orbit.
"""
from contextlib import closing
from datetime import timedelta
import json, math
from pathlib import Path
import unittest
import numpy as np
from skyfield.api import EarthSatellite,load,load_file,wgs84
from skyfield.framelib import itrs
from skyfield.toposlib import ITRSPosition
from skyfield.units import Distance
from astronomy import utc
from observatory.final_sky.geometry import (sky_chart,polar,live_positions,search_transits,
    transit_geometry,separation,minimise,root,ROOT)

class FinalSkyTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.ts=load.timescale(builtin=True);cls.eph=load_file(str(ROOT/'assets/de440s.bsp'))
  cls.rows=json.loads((ROOT/'tests/fixtures/stations.json').read_text())
  cls.when=utc('2026-11-09T00:00Z')
  cls.p={'name':'Public Nashville sample','lat':36.1627,'lon':-86.7816,'elevation':0,'observingHeight':0,'horizon':[]}
 @classmethod
 def tearDownClass(cls):cls.eph.close()
 def test_stable_angles_and_independent_analytic_minimum(self):
  self.assertAlmostEqual(float(separation([1,0,0],[1,1e-9,0])),math.degrees(1e-9),places=12)
  self.assertAlmostEqual(float(separation([1,0,0],[-1,0,0])),180)
  x,y=minimise(lambda t:(t-.1234)**2,-2,3)
  self.assertAlmostEqual(x,.1234,delta=.002);self.assertLess(y,1e-6)
  self.assertAlmostEqual(root(lambda t:t*t-.25,0,1),.5,delta=.002)
 def test_chart_epochs_boundaries_and_saved_horizon(self):
  d=sky_chart(self.eph,self.ts,self.p,None,self.when)
  self.assertGreater(len(d['stars']),300)
  self.assertTrue(all(0<=s['el']<=90 and 0<=s['az']<360 for s in d['stars']))
  self.assertEqual(d['poleAltitude'],self.p['lat'])
  self.assertTrue(any(target['id']=='M31' and target['extent']==3 for target in d['targets']))
  self.assertTrue(all(0<=target['el']<=90 and 0<=target['az']<360 for target in d['targets']))
  blocked={**self.p,'horizon':[{'from':0,'to':360,'height':90}]}
  b=sky_chart(self.eph,self.ts,blocked,None,self.when)
  self.assertTrue(all(not s['clear'] for s in b['stars']+b['targets']))
  later=sky_chart(self.eph,self.ts,self.p,None,self.when+timedelta(hours=6))
  a={s['id']:s for s in d['stars']};z={s['id']:s for s in later['stars']}
  self.assertTrue(any(abs(a[k]['az']-z[k]['az'])>30 for k in a.keys()&z.keys()))
 def test_polar_both_hemispheres_reference_offset_and_upright_direction(self):
  for latitude,north in ((36,True),(-36,False),(0,True)):
   p={**self.p,'lat':latitude};d=polar(self.eph,self.ts,p,self.when)
   self.assertEqual(d['north'],north);self.assertEqual(d['poleAltitude'],abs(latitude))
   self.assertTrue(.4<d['offset']<1.5)
   self.assertAlmostEqual(math.hypot(d['x'],d['y']),d['offset'],delta=.001)
   # Independent local tangent dot products: centre is the true pole,
   # positive screen x is right, positive y is towards zenith.
   a=math.radians(d['starAzimuth']);h=math.radians(d['starAltitude']);lat=math.radians(abs(latitude));bearing=0 if north else math.pi
   tangent_right=-math.cos(h)*math.sin(a-bearing)
   tangent_up=math.sin(h)*math.cos(lat)-math.cos(h)*math.cos(a-bearing)*math.sin(lat)
   self.assertEqual(d['x']>0,tangent_right>0);self.assertEqual(d['y']>0,tangent_up>0)
 def test_current_stations_move_and_stale_future_suppress_coordinates(self):
  a=live_positions(self.rows,self.ts,self.eph,self.p,self.when)
  b=live_positions(self.rows,self.ts,self.eph,self.p,self.when+timedelta(seconds=10))
  for x,y in zip(a['stations'],b['stations']):
   self.assertTrue(x['usable']);self.assertNotEqual(x['lon'],y['lon']);self.assertEqual(len(x['track']),181)
  for hours in (72,-48):
   for s in live_positions(self.rows,self.ts,self.eph,self.p,self.when+timedelta(hours=hours))['stations']:
    self.assertFalse(s['usable']);self.assertNotIn('lat',s);self.assertNotIn('track',s)
 def test_independent_ray_ellipsoid_transit_fixture_and_dense_contacts(self):
  # Independently construct a site where station-to-Sun geometric ray meets
  # WGS84. Apparent light-time shifts the crossing slightly; tolerance 50 ms.
  t=self.ts.from_datetime(self.when);sat=EarthSatellite.from_omm(self.ts,self.rows[0])
  r=sat.at(t).frame_xyz(itrs).km;b=(self.eph['sun']-self.eph['earth']).at(t).frame_xyz(itrs).km
  d=(r-b)/np.linalg.norm(r-b);axes=np.array([6378.137,6378.137,6356.752314245])
  aa=np.sum((d/axes)**2);bb=2*np.sum(r*d/axes**2);cc=np.sum((r/axes)**2)-1
  k=(-bb-math.sqrt(bb*bb-4*aa*cc))/(2*aa)
  geo=wgs84.geographic_position_of(ITRSPosition(Distance(km=r+k*d)).at(t))
  p={**self.p,'lat':float(geo.latitude.degrees),'lon':float(geo.longitude.degrees)}
  result=search_transits(self.rows,self.ts,self.eph,p,None,self.when-timedelta(seconds=10),hours=.01)
  event=next(e for e in result['events'] if e['station']=='ISS' and e['target']=='Sun')
  self.assertTrue(event['disc']);self.assertIn('UNCONFIRMED',event['status'])
  self.assertLess(abs((utc(event['time'])-self.when).total_seconds()),.05)
  self.assertTrue(.5<event['duration']<.9)
  # Separate 1-ms exhaustive grid, no minimiser/root finder involved.
  dates=[self.when+timedelta(seconds=i/1000) for i in range(-600,601)]
  site=wgs84.latlon(p['lat'],p['lon']);obs=self.eph['earth']+site
  sep,rad,*_=transit_geometry(sat,site,obs,self.eph,self.ts,'sun',dates)
  inside=np.flatnonzero(sep<rad)
  self.assertAlmostEqual((dates[inside[-1]]-dates[inside[0]]).total_seconds(),event['duration'],delta=.004)
  self.assertLess(abs((dates[int(np.argmin(sep))]-utc(event['time'])).total_seconds()),.004)
  p['horizon']=[{'from':0,'to':360,'height':90}]
  self.assertFalse(search_transits(self.rows,self.ts,self.eph,p,None,self.when-timedelta(seconds=10),hours=.01)['events'])
 def test_lunar_close_approach_is_not_called_transit_and_stale_search_is_empty(self):
  result=search_transits(self.rows,self.ts,self.eph,self.p,None,self.when)
  event=next(e for e in result['events'] if e['target']=='Moon')
  self.assertFalse(event['disc']);self.assertIsNone(event['duration']);self.assertIn('no model crossing',event['status'])
  for hours in (48,-48):
   d=search_transits(self.rows,self.ts,self.eph,self.p,None,self.when+timedelta(hours=hours))
   self.assertFalse(d['events']);self.assertEqual(len(d['coverage']),2)
 def test_published_vallado_sgp4_reference_not_self_generated(self):
  from skyfield.sgp4lib import TEME
  # Vallado et al. AIAA 2006-6753 verification case 00005, epoch result.
  # Independent published TEME km vector; tolerant of UT1 rounding (< 1 m).
  sat=EarthSatellite('1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753',
      '2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667','Vanguard',self.ts)
  np.testing.assert_allclose(sat.at(sat.epoch).frame_xyz(TEME).km,[7022.46529266,-1400.08296755,0.03995155],rtol=0,atol=.001)
 def test_independent_lunar_station_alignment(self):
  # A second ray/ellipsoid construction uses Tiangong and the Moon. Search
  # a bounded orbit for an above-horizon intersection, then refine locally.
  sat=EarthSatellite.from_omm(self.ts,self.rows[1]);axes=np.array([6378.137,6378.137,6356.752314245])
  for minute in range(90):
   when=self.when+timedelta(minutes=minute);t=self.ts.from_datetime(when)
   r=sat.at(t).frame_xyz(itrs).km;b=(self.eph['moon']-self.eph['earth']).at(t).frame_xyz(itrs).km
   d=(r-b)/np.linalg.norm(r-b);aa=np.sum((d/axes)**2);bb=2*np.sum(r*d/axes**2);cc=np.sum((r/axes)**2)-1
   if bb*bb-4*aa*cc<0:continue
   k=(-bb-math.sqrt(bb*bb-4*aa*cc))/(2*aa)
   if k<0:continue
   geo=wgs84.geographic_position_of(ITRSPosition(Distance(km=r+k*d)).at(t))
   p={**self.p,'lat':float(geo.latitude.degrees),'lon':float(geo.longitude.degrees)}
   result=search_transits(self.rows,self.ts,self.eph,p,None,when-timedelta(seconds=10),hours=.01)
   found=[e for e in result['events'] if e['station']=='Tiangong' and e['target']=='Moon']
   if found:
    e=found[0];self.assertTrue(e['disc']);self.assertLess(abs((utc(e['time'])-when).total_seconds()),.05);self.assertGreater(e['duration'],.1);return
  self.fail('Constructed lunar alignment not recovered')
 def test_helper_uses_bounded_stdin_and_no_network_for_fixture(self):
  from unittest.mock import patch
  import socket
  from observatory.final_sky.geometry import build
  with patch.object(socket,'socket',side_effect=AssertionError('No network')):
   d=build({'kind':'polar'},Path('/tmp/unused'),True)
  self.assertTrue(d['fixture']);self.assertNotIn('lat',d);self.assertNotIn('lon',d)
