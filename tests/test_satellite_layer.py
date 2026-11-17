from contextlib import closing
from datetime import timedelta
import json,socket,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from skyfield.api import load,load_file
from astronomy import utc
from observatory.final_sky.satellite_layer import calculate,cached_rows
from observatory.final_sky.geometry import build,ROOT
class SatelliteLayerTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.ts=load.timescale(builtin=True);cls.eph=load_file(str(ROOT/'assets/de440s.bsp'));cls.rows=json.loads((ROOT/'tests/fixtures/stations.json').read_text());cls.catalog={25544:'ISS',48274:'Tiangong'}
  cls.p={'lat':36.1627,'lon':-86.7816,'elevation':0,'horizon':[]};cls.now=utc('2026-11-09T00:00Z')
 @classmethod
 def tearDownClass(cls):cls.eph.close()
 def test_moves_and_observer_changes_direction_without_network(self):
  with patch.object(socket,'socket',side_effect=AssertionError('No network')):
   a=calculate(self.rows,self.catalog,self.ts,self.eph,self.p,None,self.now)
   b=calculate(self.rows,self.catalog,self.ts,self.eph,self.p,None,self.now+timedelta(seconds=5))
   c=calculate(self.rows,self.catalog,self.ts,self.eph,{**self.p,'lon':0},None,self.now)
  self.assertEqual(len(a['objects']),2)
  for x,y,z in zip(a['objects'],b['objects'],c['objects']):self.assertNotEqual(x['az'],y['az']);self.assertNotEqual(x['el'],z['el'])
 def test_stale_future_missing_and_bad_entry_never_fabricate_markers(self):
  for hour in (80,-24):
   d=calculate(self.rows,{**self.catalog,123:'Missing'},self.ts,self.eph,self.p,None,self.now+timedelta(hours=hour));self.assertFalse(d['objects']);self.assertEqual(len(d['withheld']),3)
  bad={**self.rows[0],'MEAN_MOTION':float('nan')}
  d=calculate([bad,self.rows[1]],self.catalog,self.ts,self.eph,self.p,None,self.now);self.assertEqual([s['id'] for s in d['objects']],[48274])
 def test_saved_horizon_blocks_potential_geometry(self):
  p={**self.p,'horizon':[{'from':0,'to':360,'height':90}]}
  d=calculate(self.rows,self.catalog,self.ts,self.eph,p,None,self.now)
  self.assertTrue(all(not o['clear'] and not o['potential'] for o in d['objects']))
 def test_chart_toggle_uses_now_and_off_does_not_read_or_calculate_layer(self):
  with tempfile.TemporaryDirectory() as tmp,patch.object(socket,'socket',side_effect=AssertionError('No network')):
   off=build({'kind':'chart','time':'2026-11-10T01:00Z'},Path(tmp),True)
   on=build({'kind':'chart','time':'2026-11-10T01:00Z','satellites':True},Path(tmp),True)
  self.assertNotIn('satellites',off);self.assertIn('satellites',on);self.assertEqual(on['time'],'2026-11-09T00:00:00.000Z')
 def test_cached_watchlist_ids_only_no_unselected_bulk_objects(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);(p/'settings.json').write_text(json.dumps({'observing':{'watchlist':[{'number':20580,'name':'Hubble'}]}}))
   _,catalog=cached_rows(p,True,ROOT);self.assertEqual(set(catalog),{25544,48274,20580})
