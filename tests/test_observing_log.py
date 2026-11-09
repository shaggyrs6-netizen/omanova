from concurrent.futures import ThreadPoolExecutor
from importlib import import_module
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

log = import_module("observatory.observing-log.observing_log")


class ObservingLogTests(unittest.TestCase):
    def test_concurrent_saves_preserve_entries_and_sort_by_instant(self):
        entries = [
            {"seen": "ISS", "place": "Field", "notes": "First line\nSecond line",
             "observed": "2026-11-09T17:42-06:00"},
            {"seen": "Meteor", "place": "Park", "observed": "2026-11-09T18:40-05:00"},
        ]
        with TemporaryDirectory() as state, ThreadPoolExecutor(max_workers=2) as executor:
            directory = Path(state)
            list(executor.map(lambda payload: log.add_observation(directory, payload), entries))
            saved = json.loads((directory / log.FILENAME).read_text())["entries"]
        self.assertEqual([entry["seen"] for entry in saved], ["ISS", "Meteor"])
        self.assertEqual(saved[0]["notes"], entries[0]["notes"])
        self.assertEqual(saved[0]["observed"], entries[0]["observed"])

    def test_invalid_entry_or_corrupt_log_cannot_overwrite_saved_data(self):
        payload = {"seen": "ISS", "place": "Field", "observed": "2026-11-09T17:42-06:00"}
        with TemporaryDirectory() as state:
            directory = Path(state)
            path = directory / log.FILENAME
            log.add_observation(directory, payload)
            before = path.read_bytes()
            with self.assertRaises(ValueError):
                log.add_observation(directory, {**payload, "observed": "2026-02-31T17:42"})
            self.assertEqual(path.read_bytes(), before)
            path.write_text("corrupt log")
            with self.assertRaises(ValueError):
                log.add_observation(directory, payload)
            self.assertEqual(path.read_text(), "corrupt log")
