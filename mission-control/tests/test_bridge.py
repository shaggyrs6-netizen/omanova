import importlib.util,json,sys,tempfile,unittest,subprocess
from pathlib import Path
from datetime import UTC,datetime,timedelta
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('live_bridge',ROOT/'mission-control/live_bridge.py');bridge=importlib.util.module_from_spec(spec);spec.loader.exec_module(bridge)
NOW=datetime(2026,11,17,18,tzinfo=UTC)
class BridgeTests(unittest.TestCase):
 def test_freshness_rejects_old_future_and_invalid(self):
  self.assertTrue(bridge.fresh(NOW.isoformat(),NOW,15))
  for v in (None,'bad',(NOW-timedelta(seconds=16)).isoformat(),(NOW+timedelta(seconds=1)).isoformat(),NOW.replace(tzinfo=None).isoformat()):self.assertFalse(bridge.fresh(v,NOW,15))
 def card_fixture(self):
  p={'lat':36.1627,'lon':-86.7816,'timezone':'America/Chicago'}
  event={'source_id':25544,'element_epoch':(NOW-timedelta(hours=1)).isoformat(),'start':(NOW+timedelta(hours=1)).isoformat(),'end':(NOW+timedelta(hours=1,minutes=5)).isoformat(),'name':'ISS','rise':{'direction':'NW'},'culmination':{'el':42}}
  snap={'generated':NOW.isoformat(),'demo':False,'place':p,'events':[event]}
  return p,snap
 def run_cards(self,p,snap,weather=None,settings=None):
  values={'snapshot.json':snap,'weather.json':weather or {}}
  return bridge.cards(Path('/fixture'),settings or {},p,NOW,lambda path,default:values.get(path.name,default),lambda x:datetime.fromisoformat(x.replace('Z','+00:00')),lambda _: 'public',lambda x:x)
 def test_pass_keeps_visibility_unconfirmed(self):
  p,s=self.card_fixture();d=self.run_cards(p,s);self.assertIn('ISS',d['passes']['25544']['value']);self.assertIn('unconfirmed',d['passes']['25544']['detail']);self.assertNotIn('GO',str(d))
 def test_stale_snapshot_location_mismatch_and_demo_withhold(self):
  for key,value in [('generated',(NOW-timedelta(minutes=4)).isoformat()),('generated',(NOW+timedelta(seconds=1)).isoformat()),('demo',True),('place',{'lat':0,'lon':0})]:
   p,s=self.card_fixture();s[key]=value;self.assertEqual(self.run_cards(p,s)['passes']['25544']['value'],'Predictions unavailable')
 def test_stale_or_future_elements_withhold_pass(self):
  for age in (49,-7):
   p,s=self.card_fixture();s['events'][0]['element_epoch']=(NOW-timedelta(hours=age)).isoformat();self.assertEqual(self.run_cards(p,s)['passes']['25544']['value'],'Predictions unavailable')
 def test_weather_optin_location_and_age(self):
  p,s=self.card_fixture();hour=NOW.replace(minute=0,second=0,microsecond=0);weather={'key':'public','fetched':NOW.isoformat(),'data':{hour:{'cloud_cover':91}}}
  self.assertEqual(self.run_cards(p,s,weather,{'weather':True})['weather']['value'],'Cloud 91%')
  self.assertEqual(self.run_cards(p,s,weather,{'weather':False})['weather']['value'],'Weather unavailable')
  for update in ({'key':'other'},{'fetched':(NOW-timedelta(hours=7)).isoformat()},{'fetched':(NOW+timedelta(seconds=1)).isoformat()}):
   self.assertEqual(self.run_cards(p,s,{**weather,**update},{'weather':True})['weather']['value'],'Weather unavailable')
 def test_launch_feed_respects_optin_and_age(self):
  p,s=self.card_fixture();cache={'fixture':False,'fetched':NOW.isoformat(),'launches':[{'name':'Public fixture launch','net':(NOW+timedelta(hours=1)).isoformat(),'status':'Schedule uncertain'}]}
  def check(settings,c):
   values={'snapshot.json':s,'launches.json':c}
   return bridge.cards(Path('/fixture'),settings,p,NOW,lambda path,default:values.get(path.name,default),lambda x:datetime.fromisoformat(x.replace('Z','+00:00')),lambda _:'public',lambda x:x)['launch']
  self.assertEqual(check({'launches':True},cache)['value'],'Public fixture launch')
  self.assertIn('visibility unconfirmed',check({'launches':True},cache)['detail'])
  for settings,c in [({'launches':False},cache),({'launches':True},{**cache,'fixture':True}),({'launches':True},{**cache,'fetched':(NOW-timedelta(hours=7)).isoformat()})]:self.assertEqual(check(settings,c)['value'],'Launch data unavailable')
 def test_read_only_geometry_integration(self):
  with tempfile.TemporaryDirectory() as temp:
   state=Path(temp)/'data/omasky';state.mkdir(parents=True)
   settings={'profiles':[{'id':'public','name':'Public Nashville fixture','lat':36.1627,'lon':-86.7816,'elevation':0}],'active':'public','online':False,'weather':False,'launches':False}
   (state/'settings.json').write_text(json.dumps(settings))
   rows=json.loads((ROOT/'tests/fixtures/stations.json').read_text())
   for r in rows:r['EPOCH']=(datetime.now(UTC)-timedelta(hours=1)).replace(tzinfo=None).isoformat(timespec='microseconds')
   (state/'orbit.json').write_text(json.dumps({'data':rows}))
   before={str(p):p.read_bytes() for p in Path(temp).rglob('*') if p.is_file()}
   # Block socket connections in the child, not just HTTP helpers.
   code="import socket,runpy,sys; socket.socket.connect=lambda *a:(_ for _ in ()).throw(RuntimeError('Network forbidden')); sys.argv=sys.argv[1:];runpy.run_path(sys.argv[0],run_name='__main__')"
   result=subprocess.run([sys.executable,'-B','-c',code,str(ROOT/'mission-control/live_bridge.py'),'--runtime',str(ROOT),'--state',str(state)],capture_output=True,text=True,timeout=20)
   self.assertEqual(result.returncode,0,result.stderr);d=json.loads(result.stdout);self.assertEqual(d['mode'],'live');self.assertGreater(len(d['chart']['stars']),100);self.assertEqual(len(d['satellites']['objects']),2)
   self.assertEqual(before,{str(p):p.read_bytes() for p in Path(temp).rglob('*') if p.is_file()})
   for r in rows:r['EPOCH']=(datetime.now(UTC)-timedelta(hours=49)).replace(tzinfo=None).isoformat(timespec='microseconds')
   (state/'orbit.json').write_text(json.dumps({'data':rows}))
   result=subprocess.run([sys.executable,'-B','-c',code,str(ROOT/'mission-control/live_bridge.py'),'--runtime',str(ROOT),'--state',str(state)],capture_output=True,text=True,timeout=20)
   self.assertEqual(result.returncode,0);d=json.loads(result.stdout);self.assertEqual(d['satellites']['objects'],[]);self.assertEqual(len(d['satellites']['withheld']),2)
if __name__=='__main__':unittest.main()
