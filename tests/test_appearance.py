"""Appearance persistence must not alter private observing state."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from appearance import save

class AppearanceTests(unittest.TestCase):
    def test_modes_persist_without_changing_observing_data(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);protected={'settings.json':'{"profiles":["private sample"]}','observing-log.json':'private log','trip.json':'manual horizons'}
            for name,text in protected.items():(p/name).write_text(text)
            for mode in ('desktop','observatory'):
                save(p,mode)
                self.assertEqual(json.loads((p/'appearance.json').read_text()),{'schema':1,'mode':mode})
                self.assertEqual((p/'appearance.json').stat().st_mode&0o777,0o600)
                self.assertTrue(all((p/name).read_text()==text for name,text in protected.items()))
            before=(p/'appearance.json').read_bytes()
            with self.assertRaises(ValueError):save(p,'unknown')
            self.assertEqual((p/'appearance.json').read_bytes(),before)
