from copy import deepcopy
from datetime import datetime,timedelta,timezone
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
from urllib.error import HTTPError
from worker import read
from astronomy import iso
from observatory.events.launches import normalise,stream_url
from observatory.follow.follow import (DEFAULT,prefs,initialise,command,changes,apply_snapshot,refresh,view,
                                      request_json,fixtures,time_label)
NOW=datetime(2026,11,14,18,tzinfo=timezone.utc)
FIXTURE=Path(__file__).resolve().parents[1]/'observatory/events/launch-fixture.json'

class FollowTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.path=Path(self.tmp.name)
        self.state=initialise(self.path,True,NOW);self.row=self.state['rows'][0];self.id=self.row['id'];self.send=Mock(return_value=True)
    def follow(self):
        self.state['prefs']['favourites']=[self.id]
        apply_snapshot(self.state,[self.row],iso(NOW),NOW,self.send,True)
    def update(self,scenario,seconds=60):
        rows,fetched,now=fixtures(self.state,scenario,NOW+timedelta(seconds=seconds))
        apply_snapshot(self.state,rows,fetched,now,self.send,True);self.state['rows']=rows;self.state['fetched']=fetched
        return now
    def test_initial_and_favourite_are_silent(self):
        self.state['prefs']['alerts']=True;self.follow();self.send.assert_not_called()
        self.assertEqual(self.state['history'],[])
    def test_delay_notifies_once_repeated_snapshot_deduplicates(self):
        self.follow();self.state['prefs']['alerts']=True;self.update('delay');self.update('delay',120)
        self.assertEqual(self.send.call_count,1);self.assertEqual(len(self.state['history']),1)
        self.assertIn('Delayed:',self.state['history'][0]['messages'][0]);self.assertEqual(self.state['history'][0]['delivery'],'Sent')
    def test_hold_is_not_scrub_and_explicit_scrub_is_distinct(self):
        self.follow();self.state['prefs']['alerts']=True;self.update('hold');self.update('scrub',120)
        self.assertEqual(self.send.call_count,2)
        self.assertIn('Source reports scrub',self.state['history'][0]['messages'][0])
        self.assertIn('not a confirmed scrub',self.state['history'][1]['messages'][0])
    def test_negated_status_is_not_scrub(self):
        self.assertEqual(changes(self.row,{**self.row,'status':'Not scrubbed'}),[])
    def test_cancel_explicit_and_launched_updates_ignored(self):
        self.assertIn('cancellation',changes(self.row,{**self.row,'status':'Cancelled'})[0][1])
        for status in (3,4,6,7):self.assertEqual(changes(self.row,{**self.row,'statusId':status,'net':iso(NOW+timedelta(days=1))}),[])
    def test_alerts_off_advance_baseline_without_catchup(self):
        self.follow();self.update('delay');self.state['prefs']['alerts']=True;self.update('delay',120)
        self.send.assert_not_called();self.assertEqual(len(self.state['history']),1)
    def test_independent_categories(self):
        self.follow();self.state['prefs'].update(alerts=True,delayAlerts=False,statusAlerts=True)
        self.update('delay');self.send.assert_not_called();self.update('hold',120);self.assertEqual(self.send.call_count,1)
    def test_coarse_time_is_schedule_change_not_exact_delay(self):
        new={**self.row,'precision':'DAY','net':iso(NOW+timedelta(days=1))}
        delta=changes(self.row,new);self.assertEqual(delta[0][0],'schedule');self.assertIn('time TBD',delta[0][1])
        self.assertNotIn('00:00',time_label(new))
    def test_missing_feed_entry_retains_favourite_without_alert(self):
        self.follow();self.state['prefs']['alerts']=True;self.update('missing')
        self.send.assert_not_called();rows=view(self.state,True,NOW)['rows'];kept=next(r for r in rows if r['id']==self.id)
        self.assertTrue(kept['favourite']);self.assertFalse(kept['available']);self.assertFalse(kept['fresh'])
    def test_stale_gap_and_out_of_order_do_not_notify(self):
        self.follow();self.state['prefs']['alerts']=True;new={**self.row,'net':iso(NOW+timedelta(days=1))}
        apply_snapshot(self.state,[new],iso(NOW+timedelta(hours=4)),NOW+timedelta(hours=4),self.send,True)
        apply_snapshot(self.state,[self.row],iso(NOW+timedelta(hours=1)),NOW+timedelta(hours=4),self.send,True)
        self.send.assert_not_called();self.assertEqual(len(self.state['history']),1)
    def test_notification_failure_retries_without_duplicate_after_success(self):
        self.follow();self.state['prefs']['alerts']=True;self.send.side_effect=[False,True]
        now=self.update('delay');self.assertEqual(len(self.state['pending']),1)
        apply_snapshot(self.state,self.state['rows'],self.state['fetched'],now+timedelta(seconds=1),self.send,True)
        apply_snapshot(self.state,self.state['rows'],self.state['fetched'],now+timedelta(seconds=2),self.send,True)
        self.assertEqual(self.send.call_count,2);self.assertEqual(self.state['pending'],[])
    def test_command_persistence_reset_and_unfollow(self):
        command(self.path,True,'init',{},NOW,send=self.send)
        command(self.path,True,'favourite',{'id':self.id,'on':True},NOW,send=self.send)
        p=read(self.path/'state.json',{})['prefs'];p.update(alerts=True,downloads=True)
        command(self.path,True,'preferences',p,NOW,send=self.send)
        command(self.path,True,'simulate',{'scenario':'delay'},NOW+timedelta(seconds=60),send=self.send)
        command(self.path,True,'init',{},NOW+timedelta(seconds=120),send=self.send)
        state=read(self.path/'state.json',{});self.assertEqual(state['prefs']['favourites'],[self.id]);self.assertFalse(state['prefs']['alerts']);self.assertFalse(state['prefs']['downloads'])
        command(self.path,True,'favourite',{'id':self.id,'on':False},NOW+timedelta(seconds=121),send=self.send)
        self.assertEqual(read(self.path/'state.json',{})['prefs']['favourites'],[])
    def test_no_network_without_consent(self):
        fetch=Mock()
        with self.assertRaises(ValueError):refresh(self.state,NOW,fetch,self.send)
        fetch.assert_not_called()
    def test_cache_and_budget_include_repeated_upcoming_requests(self):
        fetch=Mock(return_value=read(FIXTURE,{}))
        request_json(self.state,'upcoming','https://example.invalid',NOW,fetch)
        request_json(self.state,'upcoming','https://example.invalid',NOW+timedelta(minutes=1),fetch)
        self.assertEqual(fetch.call_count,1)
        for i in range(1,4):request_json(self.state,'upcoming','https://example.invalid',NOW+timedelta(minutes=15*i),fetch)
        self.assertEqual(len(self.state['requestHistory']),4)
        self.state['requestHistory']=[iso(NOW+timedelta(minutes=45))]*9
        with self.assertRaises(ValueError):request_json(self.state,'upcoming','https://example.invalid',NOW+timedelta(minutes=61),fetch)
    def test_missing_favourite_uses_detail_and_rate_error_cools_down(self):
        self.follow();self.state['prefs']['downloads']=True
        other=read(FIXTURE,{})['results'][1]
        detail=read(FIXTURE,{})['results'][0]
        fetch=Mock(side_effect=[{'results':[other]},detail])
        refresh(self.state,NOW+timedelta(seconds=1),fetch,self.send)
        self.assertEqual(fetch.call_count,2);self.assertIn(self.id,{r['id'] for r in self.state['rows']})
        failing=Mock(side_effect=HTTPError('https://example.invalid',429,'limited',{},None))
        refresh(self.state,NOW+timedelta(minutes=16),failing,self.send)
        self.assertIn('Cached rows kept',self.state['error']);self.assertEqual(self.state['blockedUntil'],iso(NOW+timedelta(minutes=76)))
        with self.assertRaises(ValueError):refresh(self.state,NOW+timedelta(minutes=17),failing,self.send)
        self.assertEqual(failing.call_count,1)
    def test_live_restart_establishes_fresh_baseline_without_backlog(self):
        self.follow();self.state['needsBaseline']=[self.id];self.state['prefs']['alerts']=True
        self.update('delay');self.send.assert_not_called()
        self.update('original',120);self.assertEqual(self.send.call_count,1)
    def test_outage_keeps_baseline_and_no_false_cancel(self):
        command(self.path,True,'init',{},NOW,send=self.send)
        command(self.path,True,'favourite',{'id':self.id,'on':True},NOW,send=self.send)
        before=read(self.path/'state.json',{})['baseline']
        command(self.path,True,'simulate',{'scenario':'outage'},NOW+timedelta(seconds=60),send=self.send)
        after=read(self.path/'state.json',{})
        self.assertEqual(before,after['baseline']);self.send.assert_not_called();self.assertEqual(after['history'],[])

    def test_corrupt_saved_state_is_not_overwritten(self):
        path=self.path/'state.json';path.write_text('not valid json')
        with self.assertRaises(ValueError):initialise(self.path,True,NOW)
        self.assertEqual(path.read_text(),'not valid json')
    def test_notification_escaping_and_delivery_errors(self):
        from observatory.follow.follow import notify
        import subprocess
        event={'name':'<b>Sample</b>','messages':['<img src="https://invalid.example">']}
        send=Mock()
        self.assertTrue(notify(event,True,send))
        args=send.call_args.args[0]
        self.assertIn('[Preview',args[-2]);self.assertNotIn('<b>',args[-2]);self.assertNotIn('<img',args[-1])
        send.side_effect=subprocess.TimeoutExpired('notify-send',5)
        self.assertFalse(notify(event,True,send))

    def test_live_open_keeps_explicit_consent_and_favourites(self):
        command(self.path,False,'init',{},NOW,send=self.send)
        state=read(self.path/'state.json',{});state['rows']=[self.row];state['fetched']=iso(NOW)
        from worker import write
        write(self.path/'state.json',state)
        command(self.path,False,'favourite',{'id':self.id,'on':True},NOW,send=self.send)
        p=read(self.path/'state.json',{})['prefs'];p.update(alerts=True,downloads=True)
        command(self.path,False,'preferences',p,NOW,send=self.send)
        command(self.path,False,'open',{},NOW,send=self.send)
        state=read(self.path/'state.json',{})
        self.assertTrue(state['prefs']['alerts']);self.assertTrue(state['prefs']['downloads'])
        self.assertEqual(state['prefs']['favourites'],[self.id]);self.assertEqual(state['needsBaseline'],[self.id]);self.send.assert_not_called()
    def test_cli_rejects_other_data_directories(self):
        import subprocess,sys
        script=Path(__file__).resolve().parents[1]/'observatory/follow/follow.py'
        result=subprocess.run([sys.executable,str(script),'--root',str(self.path),'init'],capture_output=True)
        self.assertNotEqual(result.returncode,0);self.assertFalse((self.path/'sample').exists())

    def test_webcast_validation_and_invalid_preferences(self):
        for url in ('javascript:alert(1)','http://example.com','https://user:secret@example.com','https://example.com/ has space'):
            self.assertIsNone(stream_url(url))
        self.assertEqual(stream_url('https://www.youtube.com/'),'https://www.youtube.com/')
        for data in ({'alerts':'yes'},{'downloads':1},{'favourites':['bad']},{'unexpected':True}):
            with self.assertRaises(ValueError):prefs(data)
