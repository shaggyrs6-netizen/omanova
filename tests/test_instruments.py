from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from observatory.field import instruments


class InstrumentTests(unittest.TestCase):
    def test_estimate_sends_coordinates_on_stdin_and_rejects_nodata(self):
        metadata = '{"driverShortName":"GTiff","bands":[{"noDataValue":0}]}'
        with TemporaryDirectory() as directory:
            file = Path(directory)/'atlas.tif'
            file.touch()
            with patch.object(instruments, 'point', return_value=({'lat': 36.1, 'lon': -86.7}, None)):
                with patch.object(instruments, 'tool', side_effect=[metadata, '0.42']) as tool:
                    result = instruments.estimate({'path': str(file), 'source': 'active'})
                    self.assertIn('0.42 mcd/m²', result['message'])
                    self.assertNotIn('36.1', tool.call_args.args[1])
                    self.assertEqual(tool.call_args.kwargs['input_text'], '-86.7 36.1\n')
                with patch.object(instruments, 'tool', side_effect=[metadata, '0']):
                    with self.assertRaisesRegex(ValueError, 'no estimate'):
                        instruments.estimate({'path': str(file), 'source': 'active'})

    def test_plate_solution_uses_private_copy_and_reads_standard_wcsinfo_fields(self):
        with TemporaryDirectory() as directory:
            file = Path(directory)/'sky.jpg'
            file.write_bytes(b'fixture')
            def run(name, arguments, **kwargs):
                if name == 'solve-field':
                    self.assertNotEqual(Path(arguments[-1]).parent, file.parent)
                    self.assertEqual(Path(arguments[-1]).read_bytes(), b'fixture')
                    Path(arguments[arguments.index('--wcs')+1]).touch()
                    return ''
                self.assertEqual(name, 'wcsinfo')
                return 'ra_center 180\ndec_center -5\npixscale 1.5\norientation 20\n'
            with patch.object(instruments, 'tool', side_effect=run):
                self.assertIn('RA 12.00000 h', instruments.solve({'path': str(file)})['message'])
            self.assertEqual(list(file.parent.iterdir()), [file])

    def test_mount_checks_before_any_write_and_uses_atomic_coordinates(self):
        request = {'device': 'Telescope Simulator', 'target': 'M110', 'confirm': False}
        connected = 'Telescope Simulator.CONNECTION.CONNECT=On'
        with patch.object(instruments, 'tool', return_value=connected) as tool:
            with self.assertRaisesRegex(ValueError, 'Confirm'):
                instruments.mount('goto', request)
            self.assertEqual([call.args[0] for call in tool.call_args_list], ['indi_getprop'])

        request['confirm'] = True
        with patch.object(instruments, 'tool', return_value=connected) as tool:
            with patch.object(instruments, 'pointing', side_effect=ValueError('Target blocked')):
                with self.assertRaisesRegex(ValueError, 'Target blocked'):
                    instruments.mount('goto', request)
            self.assertEqual([call.args[0] for call in tool.call_args_list], ['indi_getprop'])

        with patch.object(instruments, 'tool', return_value=connected) as tool:
            with patch.object(instruments, 'pointing', return_value=(1.25, 41.5)):
                instruments.mount('goto', request)
            self.assertEqual(tool.call_args.args[1][-1],
                             'Telescope Simulator.EQUATORIAL_EOD_COORD.RA;DEC=1.250000000;41.500000000')
            self.assertTrue(all('127.0.0.1' in call.args[1] for call in tool.call_args_list))
