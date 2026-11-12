from copy import deepcopy
import gzip
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import numpy as np
from observatory.trips import terrain as t
from observatory.trips.trips import validate_config,validate_place

PLACE={'name':'Public sample','lat':36.1627,'lon':-86.7816,'elevation':0,'timezone':'America/Chicago','horizon':[{'name':'Trees','from':30,'to':80,'height':20}],'observingHeight':1.7,'useTerrain':False}

class TerrainTests(unittest.TestCase):
    def test_tile_floor_and_date_line(self):
        self.assertEqual(t.tile_id(-1,-1),'S01W001')
        lat,lon=t.ray_points(0,179.99)
        self.assertTrue((lon<0).any());self.assertTrue((lon>0).any())
        self.assertTrue(np.all((lon>=-180)&(lon<180)))
        self.assertEqual(lat.shape,(720,500))
    def test_hgt_orientation_void_and_size(self):
        grid=np.zeros((t.GRID,t.GRID),dtype='>i2');grid[0,0]=123;grid[-1,-1]=456
        decoded=t.decode(gzip.compress(grid.tobytes()))
        self.assertEqual(t.sample_grid(decoded,np.array([37,36]),np.array([-87,-86]),36,-87).tolist(),[123,456])
        with self.assertRaises(ValueError):t.decode(gzip.compress(b'bad'))
        grid[0,0]=-32768
        with self.assertRaises(ValueError):t.sample_grid(grid,np.array([37]),np.array([-87]),36,-87)
    def test_curvature_height_and_known_ridge(self):
        distance=np.array([1000.]);angle=t.angles(np.array([200.]),100.,0.,distance)[0]
        self.assertAlmostEqual(angle,5.706,delta=.02)
        self.assertLess(t.angles(np.array([200.]),100.,20.,distance)[0],angle)
        self.assertLess(t.angles(np.array([100.]),100.,0.,distance)[0],0)
    def test_manual_layers_preserved_and_north_wrap(self):
        manual=[{'from':350,'to':10,'height':20}]
        profile={'samples':[5.]*720};before=deepcopy(manual)
        self.assertEqual(t.combined_altitude(np.array([0,359.9,90]),manual,profile).tolist(),[20,20,5])
        self.assertEqual(manual,before)
    def test_no_consent_never_downloads(self):
        with tempfile.TemporaryDirectory() as d,patch.object(t,'urlopen') as fetch:
            with self.assertRaisesRegex(ValueError,'not cached'):t.download_tile(36,-87,Path(d),False,1e99)
            fetch.assert_not_called()
    def test_estimate_cache_and_height_invalidation(self):
        place=deepcopy(PLACE);before=deepcopy(place)
        grid=np.full((t.GRID,t.GRID),100,dtype='>i2')
        with tempfile.TemporaryDirectory() as d:
            state=Path(d)
            with patch.object(t,'ray_points',return_value=(np.full((720,500),36.16),np.full((720,500),-86.78))):
                profile=t.estimate(place,state,tile_loader=lambda *args:grid)
            self.assertEqual(profile['samples'],[0.]*720)
            self.assertEqual(place,before)
            with patch.object(t,'download_tile',side_effect=AssertionError('network')):
                self.assertEqual(t.load_profile(place,state),profile)
                self.assertEqual(t.estimate(place,state),profile)
            raised={**place,'observingHeight':5}
            self.assertIsNone(t.load_profile(raised,state))
            self.assertEqual(t.load_profile(place,state)['observingHeight'],1.7)
            path=state/'terrain/profiles'/(profile['key']+'.json')
            profile['samples'][0]=float('nan');path.write_text(json.dumps(profile))
            with self.assertRaises(ValueError):t.load_profile(place,state)
    def test_failure_does_not_apply_partial_terrain(self):
        place=deepcopy(PLACE);grid=np.full((t.GRID,t.GRID),-32768,dtype='>i2')
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError,'missing'):
                t.estimate(place,Path(d),tile_loader=lambda *args:grid)
            self.assertIsNone(t.load_profile(place,Path(d)))
            self.assertEqual(place,PLACE)
    def test_old_trip_manual_data_survives_validation(self):
        old=deepcopy(PLACE);old.pop('observingHeight');old.pop('useTerrain')
        new=validate_place(old)
        self.assertEqual(new['horizon'],PLACE['horizon'])
        self.assertEqual(new['observingHeight'],1.7);self.assertFalse(new['useTerrain'])
        for bad in (-1,101,float('nan'),'bad'):
            with self.assertRaises(ValueError):validate_place({**old,'observingHeight':bad})
        with self.assertRaises(ValueError):validate_place({**old,'useTerrain':'yes'})
    def test_polar_range_rejected_without_download(self):
        with tempfile.TemporaryDirectory() as d,patch.object(t,'urlopen') as fetch:
            with self.assertRaises(ValueError):t.estimate({**PLACE,'lat':80},Path(d),True)
            fetch.assert_not_called()
    def test_download_size_and_cache_boundaries(self):
        class Response:
            def __enter__(self):return self
            def __exit__(self,*a):pass
            def geturl(self):return 'https://s3.amazonaws.com/elevation-tiles-prod/skadi/N36/N36W087.hgt.gz'
            def read(self,n):return b'x'*100
        with tempfile.TemporaryDirectory() as d,patch.object(t,'urlopen',return_value=Response()),patch.object(t,'DOWNLOAD_LIMIT',50):
            with self.assertRaisesRegex(ValueError,'size limit'):t.download_tile(36,-87,Path(d),True,1e99)
            self.assertFalse(list(Path(d).iterdir()))

    def test_missing_enabled_profile_blocks_compare_without_losing_manual(self):
        from observatory.trips.trips import compare
        from datetime import datetime,timezone
        config={'home':{**deepcopy(PLACE),'useTerrain':True},'destination':deepcopy(PLACE),
                'start':'2026-11-20','end':'2026-11-20','weather':False,'horizonStore':{}}
        before=deepcopy(config)
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError,'Terrain estimate missing'):
                compare(config,Path(d),datetime(2026,11,12,tzinfo=timezone.utc),orbit={},schedule={})
        self.assertEqual(config,before)
    def test_preview_copy_leaves_live_source_untouched(self):
        import os,subprocess,sys
        from observatory.trips.trips import ROOT
        config={'home':deepcopy(PLACE),'destination':deepcopy(PLACE),
                'start':'2026-11-20','end':'2026-11-20','weather':True,'horizonStore':{}}
        with tempfile.TemporaryDirectory() as d:
            d=Path(d);source=d/'source.json';source.write_text(json.dumps(config));original=source.read_bytes()
            subprocess.run([sys.executable,str(ROOT/'observatory/trips/trips.py'),'init','--state',str(d/'preview'),
                            '--copy-trip',str(source)],check=True,env={**os.environ,'OPENBLAS_NUM_THREADS':'1'},capture_output=True)
            saved=json.loads((d/'preview/trip.json').read_text())
            self.assertEqual(source.read_bytes(),original)
            self.assertEqual(saved['home']['horizon'],PLACE['horizon']);self.assertFalse(saved['weather'])
            self.assertEqual(saved['home']['observingHeight'],1.7)

if __name__=='__main__':unittest.main()
