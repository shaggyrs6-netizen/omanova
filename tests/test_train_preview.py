import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from skyfield.api import load

from astronomy import utc
from observatory.trains.trains import designator, individual_elements, prepare


class TrainPreviewTests(unittest.TestCase):
    def test_stack_can_link_a_launch_but_cannot_count_as_a_member(self):
        launched = utc("2026-10-31T04:04:34Z")
        now = utc("2026-11-09T13:00:00Z")
        stack = {"OBJECT_NAME": "STARLINK-G15-18 STACK", "OBJECT_ID": "2026-246A",
                 "EPOCH": "2026-10-31T05:07:48Z", "NORAD_CAT_ID": 72000}
        self.assertEqual(designator([stack], "15-18", launched), "2026-246")
        with self.assertRaises(ValueError):
            designator([stack], "15-19", launched)
        self.assertEqual(individual_elements([stack], "2026-246", load.timescale(builtin=True),
                                             now, launched), {})

    def test_simulation_requires_multiple_sunlit_members(self):
        with TemporaryDirectory() as state:
            directory = Path(state)
            output = directory / "trains.json"
            prepare(output, directory, fixture=True)
            result = json.loads(output.read_text())
        self.assertTrue(result["fixture"])
        window = result["batches"][0]["windows"][0]
        self.assertGreaterEqual(window["best"]["count"], 3)
        self.assertGreaterEqual(window["start"]["altitude"], 15)
        self.assertLess(window["start"]["time"], window["end"]["time"])
        self.assertEqual(window["best"]["direction"], "SE")
