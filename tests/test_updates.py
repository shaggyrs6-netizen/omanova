import io,json,os,shutil,tarfile,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from datetime import UTC,datetime
import update_manager as u

class FakeServices:
 def __init__(self,healthy=True,active=True):self.running=active;self.ok=healthy;self.calls=[]
 def active(self):return self.running
 def stop(self):self.running=False;self.calls.append('stop')
 def start(self):self.running=True;self.calls.append('start')
 def healthy(self,*args):return self.ok

class UpdateTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name);self.state=self.root/'state';self.state.mkdir();self.runtime=self.root/'runtime';self.runtime.mkdir()
  self.config=self.root/'.config';self.plugin=self.config/'omarchy/plugins/local.omasky';self.plugin.mkdir(parents=True)
  self.env=patch.dict(os.environ,{'HOME':str(self.root),'XDG_CONFIG_HOME':str(self.config)});self.env.start();self.addCleanup(self.env.stop)
  (self.runtime/'manifest.json').write_text('{"version":"0.1.4"}');(self.runtime/'worker.py').write_text('old code')
  (self.plugin/'manifest.json').write_text('{"id":"local.omasky","version":"0.1.4"}');(self.plugin/'BarWidget.qml').write_text('old widget')
  (self.state/'runtime').symlink_to(self.runtime);self.unit=self.config/'systemd/user/omanova-worker.service';self.unit.parent.mkdir(parents=True);self.unit.write_text('owned unit')
  (self.state/'settings.json').write_text('PRIVATE LOCATION');(self.state/'observations.json').write_text('PRIVATE LOG')
  u.register(self.state,self.runtime,self.plugin)
 def prepare(self,state,ticket,previous):
  work=state/'updates/runtimes/test';runtime=work/'runtime';runtime.mkdir(parents=True);widget=work/'widget';widget.mkdir()
  (runtime/'manifest.json').write_text('{"version":"0.1.5"}');(runtime/'systemd').mkdir();(runtime/'systemd/omanova-worker.service').write_text('owned unit');(runtime/'worker.py').write_text('new')
  (widget/'manifest.json').write_text('{"id":"local.omasky","version":"0.1.5"}');(widget/'BarWidget.qml').write_text('new widget')
  return runtime,widget,'a'*40
 def test_version_release_paths_and_no_private_data_in_request(self):
  self.assertGreater(u.version('0.1.10'),u.version('0.1.9'))
  for s in ['1.0.0-rc1','../1.0.0','1.02.0']:
   with self.assertRaises(ValueError):u.version(s)
  raw={'draft':False,'prerelease':False,'tag_name':'v0.1.5','body':'notes','assets':[{'name':n,'browser_download_url':f'https://github.com/{u.REPO}/releases/download/v0.1.5/{n}'} for n in ('omanova-0.1.5.tar.gz','SHA256SUMS','SOURCE-COMMIT.txt')]}
  self.assertEqual(u.release(raw)['version'],'0.1.5');raw['assets'][0]['browser_download_url']='https://evil.invalid/archive'
  with self.assertRaises(ValueError):u.release(raw)
 def test_upgrade_switches_widget_alias_preserves_data_and_leaves_old_runtime(self):
  service=FakeServices();result=u.install(self.state,{'version':'0.1.5'},service,self.prepare)
  self.assertEqual(result['status'],'installed');self.assertEqual((self.state/'runtime').resolve().name,'runtime');self.assertNotEqual((self.state/'runtime').resolve(),self.runtime)
  self.assertEqual((self.runtime/'worker.py').read_text(),'old code');self.assertEqual((self.plugin/'BarWidget.qml').read_text(),'new widget')
  self.assertEqual((self.state/'settings.json').read_text(),'PRIVATE LOCATION');self.assertEqual((self.state/'observations.json').read_text(),'PRIVATE LOG');self.assertEqual(service.calls,['stop','start'])
  self.assertEqual(u.read(self.state/'updates/journal.json')['phase'],'complete')
 def test_failed_new_worker_restores_alias_widget_and_active_state(self):
  service=FakeServices(healthy=False)
  with self.assertRaises(ValueError):u.install(self.state,{'version':'0.1.5'},service,self.prepare)
  self.assertEqual((self.state/'runtime').resolve(),self.runtime);self.assertEqual((self.plugin/'BarWidget.qml').read_text(),'old widget');self.assertTrue(service.running)
  self.assertEqual(u.read(self.state/'updates/journal.json')['phase'],'restored');u.preflight(self.state)
 def test_customised_source_or_widget_refused_before_stopping_worker(self):
  service=FakeServices();(self.plugin/'BarWidget.qml').write_text('user edit')
  with self.assertRaises(ValueError):u.install(self.state,{'version':'0.1.5'},service,lambda *a:self.fail('No prepare'))
  self.assertEqual(service.calls,[]);self.assertEqual((self.plugin/'BarWidget.qml').read_text(),'user edit')
 def test_same_or_older_release_and_changed_unit_do_not_switch(self):
  for v in ('0.1.4','0.1.3'):
   with self.assertRaises(ValueError):u.install(self.state,{'version':v},FakeServices(),lambda *a:self.fail('No prepare'))
  self.unit.write_text('custom unit');service=FakeServices()
  with self.assertRaises(ValueError):u.install(self.state,{'version':'0.1.5'},service,self.prepare)
  self.assertEqual(service.calls,[]);self.assertEqual((self.state/'runtime').resolve(),self.runtime)
 def test_inactive_worker_stays_inactive_and_login_choice_not_changed(self):
  service=FakeServices(active=False);u.install(self.state,{'version':'0.1.5'},service,self.prepare);self.assertEqual(service.calls,[]);self.assertFalse(service.running)
 def test_interrupted_activation_can_restore_original_installation(self):
  previous=u.preflight(self.state);backup=self.state/'updates/backups/test/widget';backup.parent.mkdir(parents=True);self.plugin.rename(backup)
  u.write(self.state/'updates/journal.json',{'phase':'switching','previous':previous,'backup':str(backup),'wasActive':True})
  self.assertEqual(u.status(self.state)['status'],'recovery');service=FakeServices(active=False);u.restore(self.state,service)
  self.assertTrue(self.plugin.is_dir());self.assertTrue(service.running);u.preflight(self.state)
 def test_fixture_check_install_restore_never_touch_network_or_service(self):
  with patch.object(u,'fetch',side_effect=AssertionError('No network')),patch.object(u,'Services',side_effect=AssertionError('No services')):
   for action in ('check','launch','restore'):
    d=u.dispatch(action,self.state,fixture=True);self.assertIn('Demonstration',d['message'])
 def test_hash_mismatch_stops_before_unpack_or_environment(self):
  ticket={'version':'0.1.5','name':'omanova-0.1.5.tar.gz','assets':{'SHA256SUMS':'sums','omanova-0.1.5.tar.gz':'blob'}}
  with patch.object(u,'fetch',side_effect=[('a'*64+'  omanova-0.1.5.tar.gz').encode(),b'bad archive']),patch.object(u,'unpack',side_effect=AssertionError('No extract')):
   with self.assertRaises(ValueError):u.prepare(self.state,ticket,{'runtime':str(self.runtime)})
 def test_archive_rejects_traversal_and_external_links(self):
  for name,link in [('omanova-0.1.5/../escape',''),('omanova-0.1.5/imports','/etc')]:
   blob=self.root/'bad.tar.gz'
   with tarfile.open(blob,'w:gz') as t:
    info=tarfile.TarInfo(name)
    if link:info.type=tarfile.SYMTYPE;info.linkname=link
    else:info.size=1
    t.addfile(info,None if link else io.BytesIO(b'x'))
   destination=self.root/('extract-'+str(len(list(self.root.iterdir()))));destination.mkdir()
   with self.assertRaises(ValueError):u.unpack(blob,destination,'0.1.5')
 def test_prepare_complete_bundle_tag_and_pinned_environment_in_isolation(self):
  import hashlib
  tag=self.root/'tag';tag.mkdir();(tag/'systemd').mkdir();(tag/'qml').mkdir();(tag/'qml/Example.qml').write_text('Item {}')
  for name in (*u.WIDGET_FILES,'install','setup-runtime','worker.py','runtime_identity.py','update_manager.py'):(tag/name).write_text('fixture source')
  (tag/'manifest.json').write_text('{"version":"0.1.5","id":"io.github.shaggyrs6-netizen.omanova"}')
  (tag/'requirements.txt').write_text('example==1.0.0\n');(tag/'systemd/omanova-worker.service').write_text('owned unit');(tag/'.gitignore').write_text('.venv/\n')
  revision='b'*40;buf=io.BytesIO()
  with tarfile.open(fileobj=buf,mode='w:gz') as t:
   for p in tag.rglob('*'):t.add(p,arcname='omanova-0.1.5/'+str(p.relative_to(tag)),recursive=False)
   info=tarfile.TarInfo('omanova-0.1.5/SOURCE-COMMIT.txt');info.size=41;t.addfile(info,io.BytesIO((revision+'\n').encode()))
  blob=buf.getvalue();checksum=hashlib.sha256(blob).hexdigest()
  ticket={'version':'0.1.5','tag':'v0.1.5','name':'omanova-0.1.5.tar.gz','assets':{'SHA256SUMS':'sums','omanova-0.1.5.tar.gz':'blob','SOURCE-COMMIT.txt':'commit'}}
  payloads={'sums':(checksum+'  omanova-0.1.5.tar.gz\n').encode(),'blob':blob,'commit':(revision+'\n').encode(),u.KERNEL_URL:b'kernel'}
  commands=[]
  def run(args,**kwargs):
   commands.append(args)
   if args[0]=='git':shutil.copytree(tag,Path(args[-1]))
  with patch.object(u,'fetch',side_effect=lambda url,limit:payloads[url]),patch.object(u,'KERNEL_SHA',hashlib.sha256(b'kernel').hexdigest()),patch.object(u.subprocess,'run',side_effect=run),patch.object(u.subprocess,'check_output',return_value=revision+'\n'):
   runtime,widget,commit=u.prepare(self.state,ticket,{'runtime':str(self.runtime),'plugin':str(self.plugin)})
  self.assertEqual(commit,revision);self.assertEqual(u.read(widget/'manifest.json')['id'],'local.omasky');self.assertEqual((runtime/'assets/de440s.bsp').read_bytes(),b'kernel');self.assertEqual(u.read(runtime/'.omanova-build.json')['revision'],revision)
  self.assertEqual([c[0] for c in commands],['git','uv','uv']);self.assertEqual((self.state/'runtime').resolve(),self.runtime)
 def test_foreground_worker_refuses_activation_and_preserves_install(self):
  import fcntl
  with (self.state/'watch.lock').open('a') as f:
   fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
   with self.assertRaises(ValueError):u.install(self.state,{'version':'0.1.5'},FakeServices(active=False),self.prepare)
  self.assertEqual((self.state/'runtime').resolve(),self.runtime);u.preflight(self.state)
 def test_http_failure_makes_one_request_no_install_or_service_calls(self):
  from urllib.error import HTTPError
  with patch.object(u,'fetch',side_effect=HTTPError(u.API,500,'server unavailable',{},None)) as net,patch.object(u,'Services',side_effect=AssertionError('No service')):
   with self.assertRaises(HTTPError):u.dispatch('check',self.state)
   self.assertEqual(net.call_count,1)
 def test_status_checks_never_use_network(self):
  with patch.object(u,'fetch',side_effect=AssertionError('No network')):
   self.assertEqual(u.status(self.state)['status'],'idle')
 def test_successful_update_can_be_restored_but_not_over_later_user_edits(self):
  service=FakeServices();u.install(self.state,{'version':'0.1.5'},service,self.prepare)
  (self.plugin/'BarWidget.qml').write_text('new personal edit')
  with self.assertRaises(ValueError):u.restore(self.state,service)
  self.assertEqual((self.plugin/'BarWidget.qml').read_text(),'new personal edit')
  (self.plugin/'BarWidget.qml').write_text('new widget');u.restore(self.state,service)
  self.assertEqual((self.state/'runtime').resolve(),self.runtime);self.assertEqual((self.plugin/'BarWidget.qml').read_text(),'old widget')

 def test_quickshell_private_config_directory_does_not_hide_real_managed_widget(self):
  with patch.dict(os.environ,{'XDG_CONFIG_HOME':str(self.root/'quickshell-private-config')}):
   self.assertEqual(u.preflight(self.state)['plugin'],str(self.plugin))
 def test_launch_is_detached_and_completes_after_launcher_returns(self):
  import time
  helper=self.root/'update_manager.py'
  helper.write_text("import argparse,time,json,os\nfrom pathlib import Path\np=argparse.ArgumentParser();p.add_argument('--state');p.add_argument('action');a=p.parse_args();time.sleep(.3);s=Path(a.state);(s/'updates/result.json').write_text(json.dumps({'status':'installed','message':'SYNTHETIC detached completion'}))\n")
  u.write(self.state/'updates/ticket.json',{'version':'0.1.5','checked':u.stamp()})
  original=u.subprocess.Popen;children=[]
  def launch(*a,**kw):
   child=original(*a,**kw);children.append(child);return child
  with patch.object(u,'ROOT',self.root),patch.object(u.subprocess,'Popen',side_effect=launch):
   result=u.dispatch('launch',self.state)
  self.assertEqual(result['status'],'running');self.assertNotEqual(os.getsid(children[0].pid),os.getsid(0))
  children[0].wait(timeout=5)
  self.assertEqual(u.status(self.state)['status'],'installed');self.assertEqual((self.state/'settings.json').read_text(),'PRIVATE LOCATION')
 def test_future_check_timestamp_refuses_install_without_launching(self):
  from datetime import timedelta
  u.write(self.state/'updates/ticket.json',{'version':'0.1.5','checked':(datetime.now(UTC)+timedelta(hours=1)).isoformat()})
  with patch.object(u.subprocess,'Popen',side_effect=AssertionError('No launch')):
   with self.assertRaises(ValueError):u.dispatch('launch',self.state)
