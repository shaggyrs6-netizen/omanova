from datetime import datetime,timedelta,timezone
from pathlib import Path
from zoneinfo import ZoneInfo
from unittest.mock import patch
import json
import os
import tempfile
import unittest
from astronomy import iso
from worker import read,write
from observatory.calendar.calendar_export import catalogue,render,export,run,fold,escape,stamp
NOW=datetime(2026,11,14,18,tzinfo=timezone.utc)

def unfold(raw):return raw.decode('utf-8').replace('\r\n ','').split('\r\n')

class CalendarTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.state=Path(self.tmp.name)
        self.data=catalogue(self.state,'sample',NOW);self.rows=self.data['rows'];self.iss=next(r for r in self.rows if r['name']=='ISS')
    def test_rfc_envelope_and_utc(self):
        content=render([self.iss],NOW,'sample');lines=unfold(content)
        self.assertEqual(lines[0],'BEGIN:VCALENDAR');self.assertEqual(lines[-2],'END:VCALENDAR')
        for line in ('VERSION:2.0','STATUS:TENTATIVE','CLASS:PRIVATE','TRANSP:TRANSPARENT','DTSTART:20261114T182000Z','DTEND:20261114T200000Z'):self.assertIn(line,lines)
        self.assertNotIn(b'VALARM',content);self.assertNotIn(b'METHOD:',content);self.assertNotIn(b'ATTENDEE:',content);self.assertNotIn(b'ORGANIZER:',content)
        self.assertIn('SIMULATED',content.decode());self.assertFalse(content.replace(b'\r\n',b'').count(b'\n'))
    def test_utf8_fold_octet_limit_and_roundtrip(self):
        original='DESCRIPTION:'+escape('Moon 🌙, café; \\ '+('星🌠'*150)+'\nsecond line')
        physical=fold(original).split('\r\n')
        self.assertTrue(all(len(l.encode())<=75 for l in physical))
        self.assertEqual(''.join(l[1:] if i else l for i,l in enumerate(physical)),original)
    def test_property_injection_is_escaped(self):
        r=dict(self.iss);r['name']='X\r\nEND:VEVENT\r\nBEGIN:VEVENT;new,stuff\\'
        lines=unfold(render([r],NOW,'sample'))
        self.assertEqual(lines.count('BEGIN:VEVENT'),1);self.assertEqual(lines.count('END:VEVENT'),1)
        self.assertTrue(any('\\nEND:VEVENT' in l for l in lines if l.startswith('SUMMARY:')))
    def test_reminders_explicit_and_no_past_trigger(self):
        self.assertIn(b'TRIGGER:-PT15M',render([self.iss],NOW,'sample',15))
        out=render([self.iss],NOW+timedelta(minutes=10),'sample',15)
        self.assertNotIn(b'BEGIN:VALARM',out);self.assertIn(b'Reminder omitted',out)
        for lead in (-1,1,1000,True,'15'):
            with self.assertRaises(ValueError):render([self.iss],NOW,'sample',lead)
    def test_dst_fold_and_travel_keep_absolute_time(self):
        # Two different 01:30s at the autumn DST transition stay distinct in UTC.
        a='2026-11-01T01:30:00-05:00';b='2026-11-01T01:30:00-06:00'
        self.assertEqual(stamp(a),'20261101T063000Z');self.assertEqual(stamp(b),'20261101T073000Z')
        self.assertEqual(datetime.fromisoformat('2026-11-14T18:20:00+00:00').astimezone(ZoneInfo('Europe/London')).hour,18)
    def test_live_privacy_and_source_integrity(self):
        p=self.state/'planner.json';raw=dict(self.iss);raw['place']={'name':'PRIVATE PLACE','lat':11.123456};raw['coordinates']=[11.123456,22.654321]
        write(p,{'generated':iso(NOW),'location_id':'private-place-id','settings':{'address':'PRIVATE ADDRESS'},'events':[raw]});before=p.read_bytes()
        with patch('urllib.request.urlopen',side_effect=AssertionError('No networking')):
            rows=catalogue(self.state,'live',NOW,p)['rows'];content=render(rows,NOW,'live')
        for secret in (b'PRIVATE PLACE',b'PRIVATE ADDRESS',b'11.123456',b'private-place-id',b'22.654321'):self.assertNotIn(secret,content)
        self.assertFalse(any(l.startswith(('LOCATION:','GEO:')) for l in unfold(content)))
        self.assertEqual(p.read_bytes(),before)
    def test_stable_uids_and_separate_sample_namespace(self):
        p=self.state/'planner.json';write(p,{'generated':iso(NOW),'location_id':'one','events':[self.iss]})
        a=catalogue(self.state,'live',NOW,p)['rows'][0]['uid']
        self.assertEqual(a,catalogue(self.state,'live',NOW,p)['rows'][0]['uid']);self.assertNotEqual(a,self.iss['uid'])
        write(p,{'generated':iso(NOW),'location_id':'two','events':[self.iss]})
        self.assertNotEqual(a,catalogue(self.state,'live',NOW,p)['rows'][0]['uid'])
    def test_stale_past_source_issues_and_launches_blocked(self):
        self.assertTrue(next(r for r in self.rows if r['kind']=='launch')['blocked'])
        self.assertTrue(next(r for r in self.rows if r['visibility']=='stale')['blocked'])
        p=self.state/'planner.json'
        for data in ({'generated':iso(NOW-timedelta(minutes=4)),'events':[self.iss]},
                     {'generated':iso(NOW+timedelta(seconds=1)),'events':[self.iss]},
                     {'generated':iso(NOW),'events':[dict(self.iss,start=iso(NOW-timedelta(hours=2)),end=iso(NOW-timedelta(hours=1)))]},
                     {'generated':iso(NOW),'events':[self.iss],'issues':['PRIVATE source issue']}):
            write(p,data);r=catalogue(self.state,'live',NOW,p)['rows'][0];self.assertTrue(r['blocked'])
            with self.assertRaises(ValueError):render([r],NOW,'live')
    def test_caution_needs_explicit_choice_and_remains_tentative(self):
        poor=next(r for r in self.rows if r['conditions']['label']=='Poor')
        payload={'source':'sample','ids':[poor['id']]}
        with self.assertRaises(ValueError):export(self.state,payload,NOW)
        receipt=export(self.state,{**payload,'includeCaution':True},NOW)
        out=Path(receipt['path']).read_bytes();self.assertIn(b'Poor conditions',out);self.assertIn(b'STATUS:TENTATIVE',out)
        self.assertNotIn(b'CONFIRMED',out)
    def test_solar_safety_travels_with_event(self):
        solar=next(r for r in self.rows if 'solar eclipse' in r['name'])
        self.assertTrue(solar['caution']);out=render([solar],NOW,'sample')
        self.assertIn(b'Safety review',out);self.assertIn('front-mounted',out.decode().replace('\r\n ',''))
    def test_export_new_private_file_no_overwrite(self):
        payload={'source':'sample','ids':[self.iss['id']]}
        a=export(self.state,payload,NOW);b=export(self.state,payload,NOW)
        self.assertNotEqual(a['path'],b['path']);self.assertEqual(Path(a['path']).read_bytes(),Path(b['path']).read_bytes())
        self.assertEqual(os.stat(a['path']).st_mode&0o777,0o600)
        self.assertEqual(read(self.state/'receipt.json',{})['path'],b['path'])
    def test_export_rechecks_not_ui_supplied_event_content(self):
        bad={'source':'sample','ids':['invented-id'],'name':'FORGED EVENT'}
        with self.assertRaises(ValueError):export(self.state,bad,NOW)
        stale=next(r for r in self.rows if r['visibility']=='stale')
        with self.assertRaises(ValueError):export(self.state,{'ids':[stale['id']],'includeCaution':True},NOW)
    def test_selection_limits_and_duplicates(self):
        for ids in ([],[self.iss['id']]*2,['a']*51,'not-list',[1]):
            with self.assertRaises(ValueError):export(self.state,{'ids':ids},NOW)
    def test_expired_forecast_is_caution_and_empty_source_clear(self):
        p=self.state/'planner.json';r=dict(self.iss);r['conditions']={'label':'Favourable','fetched':iso(NOW-timedelta(hours=7))}
        write(p,{'generated':iso(NOW),'events':[r]});row=catalogue(self.state,'live',NOW,p)['rows'][0]
        self.assertTrue(row['caution']);self.assertEqual(row['conditions']['label'],'Uncertain')
        self.assertTrue(catalogue(self.state,'live',NOW,self.state/'missing')['error'])
    def test_sample_clock_and_receipt_not_copied_into_source_data(self):
        run(self.state,'init',{},NOW);run(self.state,'refresh',{'source':'sample'},NOW+timedelta(days=1))
        self.assertEqual(read(self.state/'view.json',{})['clock'],iso(NOW))
