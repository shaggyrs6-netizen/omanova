import importlib.util,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('startup_options',ROOT/'startup_options.py');startup=importlib.util.module_from_spec(spec);spec.loader.exec_module(startup)
class StartupTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.home=Path(self.tmp.name)/'home';self.home.mkdir();self.env=patch.dict(os.environ,{'HOME':str(self.home),'XDG_CONFIG_HOME':str(self.home/'.config'),'XDG_STATE_HOME':str(self.home/'.local/state'),'XDG_DATA_HOME':str(self.home/'.local/share')});self.env.start()
 def tearDown(self):self.env.stop();self.tmp.cleanup()
 def test_default_off_without_entry(self):
  self.assertFalse(startup.status()['enabled']);self.assertFalse(startup.entry_path().exists());self.assertFalse(startup.change(False)['enabled']);self.assertFalse(startup.entry_path().exists())
 def test_real_control_enable_disable_in_isolated_home(self):
  self.assertTrue(startup.change(True)['enabled']);p=startup.entry_path();text=p.read_text();self.assertIn('OnlyShowIn=Hyprland;',text);self.assertIn('" login',text);self.assertTrue(startup.status()['enabled']);self.assertFalse(startup.change(False)['enabled']);self.assertTrue(p.exists())
 def test_custom_entry_refused_unchanged(self):
  p=startup.entry_path();p.parent.mkdir(parents=True);p.write_text('[Desktop Entry]\nType=Application\nExec=/custom/command\nHidden=false\n');before=p.read_bytes()
  with self.assertRaises(ValueError):startup.change(False)
  self.assertEqual(before,p.read_bytes())
 def test_symlink_refused(self):
  p=startup.entry_path();p.parent.mkdir(parents=True);target=self.home/'original';target.write_text('original');p.symlink_to(target)
  with self.assertRaises(ValueError):startup.change(True)
  self.assertEqual(target.read_text(),'original')
 def test_control_rejection_retains_disabled_entry(self):
  with patch.object(startup,'control',side_effect=ValueError('Native provider refused')):
   with self.assertRaises(ValueError):startup.change(True)
  self.assertFalse(startup.status()['enabled'])
 def test_modified_exec_is_not_overwritten(self):
  p=startup.entry_path();p.parent.mkdir(parents=True);p.write_text(startup.content().replace(startup.command(),'/another/app'));before=p.read_bytes()
  with self.assertRaises(ValueError):startup.change(True)
  self.assertEqual(p.read_bytes(),before)
if __name__=='__main__':unittest.main()
