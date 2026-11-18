from datetime import UTC, datetime, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from astronomy import iso
from observatory.my_night import plan
from observatory.offline import offline
from worker import DEMO_NOW, read, write


class MyNightTests(unittest.TestCase):
    def test_obstructions_split_window_and_best_uses_clear_samples(self):
        samples = [{'el': el, 'horizon': mask, 'sun': sun}
                   for el, mask, sun in [(30, 10, -20), (40, 10, -20),
                                          (60, 70, -20), (45, 10, -20),
                                          (35, 10, -20), (65, 10, -10)]]
        runs = plan.windows(samples, 20, -18)
        self.assertEqual([run[1]['el'] for run in runs], [40, 45])

    def test_dst_night_uses_local_noon_boundaries(self):
        start, end = plan.night_bounds(plan.checked_night('2026-10-31'), 'America/Chicago')
        self.assertEqual(end-start, timedelta(hours=25))

    def test_reselected_timed_event_does_not_transfer_to_other_site_or_export_stale(self):
        night = DEMO_NOW.date()
        a = DEMO_NOW+timedelta(hours=1)
        b = a+timedelta(minutes=5)
        event = {'id':'test-pass','kind':'comet','name':'Fixture comet','start':iso(a),'end':iso(b),
                 'look':{'time':iso(a),'az':90,'el':20},'visibility':'possible'}
        place = {'id':'home','lat':36.16,'lon':-86.78,'elevation':0,'timezone':'America/Chicago'}
        start,end=plan.night_bounds(night,place['timezone'])
        pick={'event':event,'site':plan.place_key(place)}
        def chart(site, current):
            return plan.event_chart(pick,({}, {}, {'events':[event]}, place,current),site,
                                    start,end,DEMO_NOW,True,None,None,None,None)
        self.assertTrue(chart(place, True)[3])
        self.assertIn('inspect only', chart(place, False)[2])
        self.assertFalse(chart(place, False)[3])
        self.assertIsNone(chart({**place,'lat':35}, True)[1])

    def test_saved_list_deduplicates_and_exports_only_picked_targets(self):
        with TemporaryDirectory() as temp:
            base=Path(temp)
            state,data,guides=(base/name for name in ('my-night','omasky','offline'))
            data.mkdir()
            def run(action, **request):
                return plan.run(state,data,guides,True,{'action':action,**request},DEMO_NOW)
            run('configure',night='2026-11-09',source='active')
            result=run('add',kind='target',key='M35')
            self.assertEqual(result['rows'][0]['id'],'t:M35')
            self.assertGreater(len(result['chart']['points']),200)
            self.assertEqual(len(run('add',kind='target',key='M35')['rows']),1)
            saved=run('export')
            html=Path(saved['guide'])
            deck=offline.load_saved(guides,html.parent.name)
            self.assertEqual([row['id'] for row in deck['rows']],['t:M35'])
            self.assertTrue(deck['myNight'])
            self.assertNotIn('Public Nashville',html.read_text())
            self.assertEqual(len(run('remove',selected='t:M35')['rows']),0)
            self.assertEqual(read(state/'plan.json',{})['picks'],[])
            self.assertTrue(html.is_file())
