import json,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from runtime_identity import record,identity
class BuildIdentityTest(unittest.TestCase):
 def test_release_archive_records_exact_source_without_neighbour_git(self):
  with tempfile.TemporaryDirectory() as d,patch.dict(os.environ,{'OMANOVA_SOURCE_REVISION':''}):
   p=Path(d);(p/'manifest.json').write_text('{"version":"0.1.4"}')
   (p/'SOURCE-COMMIT.txt').write_text('a'*40+'\n');record(p)
   self.assertEqual(identity(p),{'version':'0.1.4','build':'release','revision':'a'*40})
   self.assertEqual((p/'.omanova-build.json').stat().st_mode&0o777,0o600)
 def test_missing_or_invalid_revision_does_not_replace_existing_identity(self):
  with tempfile.TemporaryDirectory() as d,patch.dict(os.environ,{'OMANOVA_SOURCE_REVISION':'bad'}):
   p=Path(d);f=p/'.omanova-build.json';f.write_text('original')
   with self.assertRaises(ValueError):record(p)
   self.assertEqual(f.read_text(),'original')
