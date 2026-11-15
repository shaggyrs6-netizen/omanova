"""Exports are explicit, private, spreadsheet-safe snapshots of the saved log."""
from datetime import datetime, UTC
from types import SimpleNamespace
import csv
from importlib import import_module
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

log=import_module('observatory.observing-log.observing_log')

class LogExportTests(unittest.TestCase):
    def test_csv_roundtrip_retains_unicode_quotes_newlines_offsets_and_log_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            log.add_observation(p,{'seen':'Moon, “Lune”','place':'Park, Tennessee','notes':'First line\nSecond "line" · café','observed':'2026-11-15T06:40-06:00'})
            before=(p/log.FILENAME).read_bytes()
            receipt=log.export_csv(p);file=Path(receipt['path'])
            with file.open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
            self.assertEqual(receipt['count'],1);self.assertEqual(rows[0]['notes'],'First line\nSecond "line" · café')
            self.assertEqual(rows[0]['seen'],'Moon, “Lune”');self.assertEqual(rows[0]['observed'],'2026-11-15T06:40-06:00')
            self.assertEqual((p/log.FILENAME).read_bytes(),before)
            self.assertEqual(stat.S_IMODE(file.stat().st_mode),0o600);self.assertEqual(stat.S_IMODE(file.parent.stat().st_mode),0o700)
            second=log.export_csv(p);self.assertNotEqual(receipt['path'],second['path']);self.assertTrue(file.exists())
    def test_formula_like_text_is_escaped_only_in_export(self):
        for text in ['=1+1','+SUM(A1)','-2+3','@SUM(A1)','  =1+1','\t=1+1','\r=1+1','\n=1+1']:
            with self.subTest(text=text),tempfile.TemporaryDirectory() as d:
                p=Path(d);entry={'id':'fixture','seen':'ISS','place':'Home','observed':'2026-11-15T06:40-06:00','notes':text}
                (p/log.FILENAME).write_text(json.dumps({'schema':1,'entries':[entry]}));before=(p/log.FILENAME).read_bytes()
                file=Path(log.export_csv(p)['path'])
                with file.open(encoding='utf-8-sig',newline='') as f:row=next(csv.DictReader(f))
                self.assertEqual(row['notes'],"'"+text);self.assertEqual((p/log.FILENAME).read_bytes(),before)
    def test_corrupt_log_or_invalid_entry_does_not_create_an_export(self):
        for value in ['broken',json.dumps({'schema':1,'entries':[{'seen':'missing fields'}]})]:
            with tempfile.TemporaryDirectory() as d:
                p=Path(d);(p/log.FILENAME).write_text(value)
                with self.assertRaises((ValueError,TypeError)):log.export_csv(p)
                self.assertEqual((p/log.FILENAME).read_text(),value);self.assertFalse((p/'exports').exists())
    def test_collision_and_symlink_export_directory_preserve_existing_files(self):
        with tempfile.TemporaryDirectory() as d,tempfile.TemporaryDirectory() as other:
            p=Path(d);(p/'exports').symlink_to(other,target_is_directory=True)
            with self.assertRaises(ValueError):log.export_csv(p)
            self.assertEqual(list(Path(other).iterdir()),[])
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)
            class FixedClock(datetime):
                @classmethod
                def now(cls, tz=None):return datetime(2026,11,15,12,tzinfo=UTC)
            with patch.object(log,'datetime',FixedClock),patch.object(log,'uuid4',return_value=SimpleNamespace(hex='a'*32)):
                first=Path(log.export_csv(p)['path']);before=first.read_bytes()
                with self.assertRaises(FileExistsError):log.export_csv(p)
                self.assertEqual(first.read_bytes(),before)
                self.assertEqual(len(list((p/'exports').iterdir())),1)
