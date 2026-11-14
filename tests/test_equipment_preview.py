from copy import deepcopy
from datetime import datetime,timedelta,timezone
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from astronomy import iso
from worker import read,write
from observatory.equipment.equipment import DEFAULT,profile,fixtures,assess,build,command

NOW=datetime(2026,11,14,18,tzinfo=timezone.utc)

class EquipmentTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.path=Path(self.tmp.name);self.rows=fixtures(NOW)
    def check(self,index,gear=None,sky='dark',**kw):
        return assess(self.rows[index],profile({'gear':gear or ['eye'],'sky':sky}),NOW,iso(NOW),sample=True,**kw)
    def test_additive_equipment_and_comet_tiers(self):
        self.assertTrue(self.check(5,['eye'])['excluded'])
        self.assertTrue(self.check(5,['eye','telescope'])['eligible'])
        self.assertTrue(self.check(5,['camera'])['excluded'])
        self.assertTrue(self.check(6,['telescope'])['uncertain'])
        self.assertFalse(self.check(6,['telescope'])['eligible'])
    def test_profile_strict_validation_and_empty_gear(self):
        self.assertEqual(profile({'gear':['eye','eye']})['gear'],['eye'])
        for raw in ({'gear':['laser']},{'filter':'yes'},{'coordinates':[1,2]},{'gear':'eye'}):
            with self.assertRaises(ValueError):profile(raw)
        r=assess(self.rows[0],profile({'gear':[]}),NOW,iso(NOW),sample=True)
        self.assertTrue(r['excluded']);self.assertFalse(r['eligible'])
    def test_wide_field_meteors_do_not_match_scope_only(self):
        self.assertTrue(self.check(3,['telescope'])['excluded'])
        self.assertTrue(self.check(3,['camera'])['eligible'])
        self.assertTrue(self.check(4,['eye'])['excluded'])
        self.assertTrue(self.check(4,['camera'])['eligible'])
    def test_sky_unknown_and_bright_remain_cautious(self):
        self.assertTrue(self.check(3,sky='unknown')['uncertain'])
        self.assertFalse(self.check(3,sky='unknown')['eligible'])
        self.assertTrue(self.check(3,sky='bright')['excluded'])
        self.assertTrue(self.check(1,sky='bright')['eligible'])
    def test_solar_safety_never_established_by_generic_equipment(self):
        r=self.check(8,['eye','binoculars','telescope','camera'])
        self.assertTrue(r['restricted']);self.assertTrue(r['excluded']);self.assertFalse(r['eligible'])
        self.assertTrue(self.check(9,['telescope'])['eligible'])
    def test_poor_stale_unconfirmed_are_never_promoted(self):
        for index in (7,10,11,12,13):self.assertFalse(self.check(index)['eligible'])
        r=deepcopy(self.rows[0]);r['recommended']=False
        self.assertFalse(assess(r,profile({}),NOW,iso(NOW))['eligible'])
    def test_expired_and_future_source_snapshots(self):
        for generated in (NOW-timedelta(minutes=4),NOW+timedelta(seconds=1)):
            r=assess(self.rows[0],profile({}),NOW,iso(generated))
            self.assertEqual(r['visibility'],'stale');self.assertFalse(r['eligible'])
    def test_event_expiry_and_past_window(self):
        for field in ('valid_until','end'):
            r=deepcopy(self.rows[0]);r[field]=iso(NOW-timedelta(seconds=1))
            if field=='end':r['start']=iso(NOW-timedelta(minutes=10))
            a=assess(r,profile({}),NOW,iso(NOW));self.assertEqual(a['visibility'],'stale');self.assertFalse(a['eligible'])
    def test_forecast_missing_expired_or_future_cannot_be_eligible(self):
        for fetched in (None,'invalid',iso(NOW-timedelta(hours=7)),iso(NOW+timedelta(minutes=1))):
            r=deepcopy(self.rows[0]);r['conditions']['fetched']=fetched
            a=assess(r,profile({}),NOW,iso(NOW));self.assertTrue(a['uncertain']);self.assertFalse(a['eligible'])
    def test_invalid_geometry_is_inspectable_not_eligible(self):
        for point in ({},{'az':999,'el':40},{'az':30,'el':-3},{'az':40,'el':float('nan')}):
            r=deepcopy(self.rows[0]);r['look']=point
            a=assess(r,profile({}),NOW,iso(NOW));self.assertIsNotNone(a);self.assertFalse(a['eligible'])
    def test_uncertain_and_excluded_controls_preserve_inspection(self):
        p=profile({'uncertain':False});view=build(p,'sample',NOW,self.path)
        self.assertTrue(all(not r['uncertain'] and not r['excluded'] for r in view['rows']))
        p['showExcluded']=True;view=build(p,'sample',NOW,self.path)
        self.assertEqual(len(view['rows']),14);self.assertTrue(any(r['restricted'] for r in view['rows']))
        p['showExcluded']=False;p['filter']=False
        self.assertEqual(len(build(p,'sample',NOW,self.path)['rows']),14)
    def test_live_import_is_read_only_sanitised_and_offline(self):
        r=deepcopy(self.rows[0]);r['coordinates']=[11.123456,22.123456];r['place_name']='PRIVATE TEST PLACE'
        path=self.path/'planner.json';write(path,{'generated':iso(NOW),'location_id':'PRIVATE LOCATION','events':[r]})
        before=path.read_bytes()
        with patch('urllib.request.urlopen',side_effect=AssertionError('Network not permitted')):
            v=build(profile({}),'live',NOW,self.path,path)
        self.assertTrue(v['rows'][0]['eligible']);self.assertEqual(path.read_bytes(),before)
        rendered=json.dumps(v);self.assertNotIn('PRIVATE',rendered);self.assertNotIn('11.123456',rendered)
    def test_source_issue_cannot_be_promoted(self):
        path=self.path/'planner.json';write(path,{'generated':iso(NOW),'events':[self.rows[0]],'issues':['private source details']})
        v=build(profile({}),'live',NOW,self.path,path)
        self.assertFalse(v['rows'][0]['eligible']);self.assertNotIn('private source details',json.dumps(v))
    def test_profile_persists_and_sample_clock_is_fixed(self):
        command(self.path,'init',{},NOW)
        p=profile({'gear':['binoculars','camera'],'sky':'moderate'})
        command(self.path,'save',p,NOW+timedelta(hours=3))
        self.assertEqual(read(self.path/'profile.json',{}),p)
        self.assertEqual(read(self.path/'view.json',{})['clock'],iso(NOW))
        command(self.path,'tick',{},NOW+timedelta(days=1))
        self.assertEqual(read(self.path/'view.json',{})['profile'],p)
    def test_empty_malformed_live_and_bad_rows(self):
        path=self.path/'missing.json'
        self.assertEqual(build(profile({}),'live',NOW,self.path,path)['rows'],[])
        path.write_text('{broken')
        self.assertTrue(build(profile({}),'live',NOW,self.path,path)['error'])
        for bad in (None,{}, {'start':'invalid','end':'invalid'}):self.assertIsNone(assess(bad,profile({}),NOW,iso(NOW)))

    def test_old_look_time_is_not_promoted(self):
        r=deepcopy(self.rows[0]);r['look']['time']=iso(NOW-timedelta(minutes=6))
        a=assess(r,profile({}),NOW,iso(NOW))
        self.assertEqual(a['visibility'],'stale');self.assertFalse(a['eligible'])
    def test_invalid_profile_preserved_without_silent_reset(self):
        path=self.path/'profile.json';path.write_text('{broken')
        with self.assertRaises(ValueError):command(self.path,'init',{},NOW)
        self.assertEqual(path.read_text(),'{broken')
