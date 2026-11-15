"""Usability data must remain local and must not hide freshness/identity gaps."""
from datetime import datetime, UTC, timedelta
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from runtime_identity import identity
from observatory.night_context import build, cached_clouds
from worker import forecast_key

ROOT=Path(__file__).resolve().parents[1]

class UsabilityTests(unittest.TestCase):
    def test_runtime_identity_only_exposes_valid_build_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'manifest.json').write_text('{"version":"0.1.3", "private":"not included"}')
            (p/'.omanova-build.json').write_text(json.dumps({'revision':'a'*40,'private':'not included'}))
            self.assertEqual(identity(p),{'version':'0.1.3','build':'local usability','revision':'a'*40})
            (p/'.omanova-build.json').write_text('{"revision":"invalid"}')
            self.assertEqual(identity(p)['revision'],'')
            (p/'manifest.json').write_text('[]');self.assertEqual(identity(p)['version'],'unknown')
    def test_identity_command_does_not_create_or_read_observing_state(self):
        with tempfile.TemporaryDirectory() as d:
            state=Path(d)/'absent'
            result=subprocess.run([str(ROOT/'.venv/bin/python'),str(ROOT/'worker.py'),'--state',str(state),'runtime-info'],capture_output=True,text=True,check=True,timeout=10)
            self.assertEqual(json.loads(result.stdout)['version'],'0.1.3');self.assertFalse(state.exists())
    def test_night_strip_is_network_free_dst_aware_and_omits_precise_place(self):
        now=datetime(2026,10,31,18,tzinfo=UTC)
        snapshot={'place':{'id':'sample','lat':40.7,'lon':-74.,'elevation':0,'name':'private sample'},'settings':{'weather':False}}
        with tempfile.TemporaryDirectory() as d, patch('observatory.night_context.system_zone',return_value='America/New_York'), patch.object(socket,'socket',side_effect=AssertionError('No network')):
            data=build(Path(d),snapshot,now)
            self.assertEqual(len(data['hours']),25)
            self.assertTrue(data['sunset']);self.assertTrue(data['sunrise'])
            self.assertNotIn('private sample',json.dumps(data));self.assertNotIn('lat',data);self.assertTrue(all(r['cloud'] is None for r in data['hours']))
    def test_weather_opt_out_and_expiry_do_not_expose_cached_clouds(self):
        now=datetime(2026,11,15,18,tzinfo=UTC);place={'id':'sample','lat':36.,'lon':-86.,'elevation':0}
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);snapshot={'place':place,'settings':{'weather':False}}
            (p/'weather.json').write_text(json.dumps({'key':forecast_key(place),'fetched':(now-timedelta(hours=7)).isoformat(),'data':{}}))
            self.assertEqual(cached_clouds(p,snapshot,now)[0],{})
            snapshot['settings']['weather']=True
            self.assertEqual(cached_clouds(p,snapshot,now)[0],{})
