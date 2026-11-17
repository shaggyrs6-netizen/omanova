"""Explicit GitHub-release updates. No automatic checks, private-data upload or sudo.

Candidate runtime and widget are prepared beside the old install. A journal
keeps enough information to restore the alias/widget if activation fails or is
interrupted. Checksums provide integrity, not independent publisher signatures.
"""
import argparse
from contextlib import contextmanager
from datetime import UTC,datetime,timedelta
import fcntl,hashlib,json,os,re,shutil,ssl,subprocess,sys,tarfile,tempfile,time
from pathlib import Path,PurePosixPath
from urllib.parse import urlsplit
from urllib.request import Request,build_opener,HTTPSHandler,HTTPRedirectHandler
import certifi

ROOT=Path(__file__).resolve().parent
REPO='shaggyrs6-netizen/omanova'
API=f'https://api.github.com/repos/{REPO}/releases/latest'
IDS=('io.github.shaggyrs6-netizen.omanova','local.omasky')
KERNEL_SHA='c1c7feeab882263fc493a9d5a5b2ddd71b54826cdf65d8d17a76126b260a49f2'
KERNEL_URL='https://ssd.jpl.nasa.gov/ftp/eph/planets/bsp/de440s.bsp'
WIDGET_FILES=('BarWidget.qml','SkyState.qml','SkyPanel.qml','Compass.qml','SettingsPage.qml','ObservingPreferences.qml')


def stamp():return datetime.now(UTC).isoformat(timespec='seconds')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text())
def write(p,data):
    p.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    with tempfile.NamedTemporaryFile('w',dir=p.parent,delete=False) as f:
        json.dump(data,f,ensure_ascii=False,allow_nan=False);f.flush();os.fsync(f.fileno());tmp=f.name
    os.replace(tmp,p)
def version(s):
    if not isinstance(s,str) or len(s)>40 or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)',s):raise ValueError('Only stable numbered releases are supported')
    return tuple(map(int,s.split('.')))
def safe_relative(s):
    p=PurePosixPath(s)
    if not s or p.is_absolute() or '..' in p.parts or '\\' in s or str(p)!=s or (s.startswith('.') and p.parts[0] not in ('.gitignore','.gitattributes','.github')):
        raise ValueError('Unsafe package path')
    return p


class Redirect(HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,url):
        parsed=urlsplit(url)
        if parsed.scheme!='https' or parsed.hostname not in ('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com'):
            raise ValueError('Unexpected download redirect')
        return super().redirect_request(req,fp,code,msg,headers,url)


def fetch(url,limit):
    p=urlsplit(url)
    if p.scheme!='https' or p.hostname not in ('api.github.com','github.com','ssd.jpl.nasa.gov'):raise ValueError('Unexpected source')
    opener=build_opener(Redirect(),HTTPSHandler(context=ssl.create_default_context(cafile=certifi.where())))
    with opener.open(Request(url,headers={'User-Agent':'OMANOVA updater','Accept':'application/vnd.github+json'}),timeout=30) as response:
        if response.status!=200:raise ValueError('Download failed')
        data=response.read(limit+1)
    if len(data)>limit:raise ValueError('Download exceeds size limit')
    return data


def release(raw):
    if not isinstance(raw,dict) or raw.get('draft') is not False or raw.get('prerelease') is not False:raise ValueError('No stable public release')
    tag=raw.get('tag_name','');v=tag.removeprefix('v');version(v)
    if tag!='v'+v:raise ValueError('Unexpected release tag')
    name=f'omanova-{v}.tar.gz';assets=raw.get('assets',[])
    if not isinstance(assets,list) or len(assets)>32:raise ValueError('Unexpected release assets')
    found={}
    for expected in (name,'SHA256SUMS','SOURCE-COMMIT.txt'):
        choices=[a for a in assets if isinstance(a,dict) and a.get('name')==expected]
        if len(choices)!=1:raise ValueError('Missing or ambiguous release assets')
        a=choices[0];url=f'https://github.com/{REPO}/releases/download/{tag}/{expected}'
        if a.get('browser_download_url')!=url:raise ValueError('Unexpected release asset URL')
        found[expected]=url
    body=raw.get('body') or ''
    if not isinstance(body,str):raise ValueError('Invalid release notes')
    return {'version':v,'tag':tag,'name':name,'assets':found,'notes':body[:12000],
            'url':f'https://github.com/{REPO}/releases/tag/{tag}','checked':stamp()}


def fingerprints(root):
    """Guard installed code/assets, excluding caches, envs, metadata and private state."""
    result={}
    for current,dirs,files in os.walk(root,followlinks=False):
        dirs[:]=[d for d in dirs if not d.startswith('.') and d not in ('__pycache__','node_modules')]
        # Internal QML import links are part of the supported source layout.
        for d in list(dirs):
            path=Path(current)/d
            if path.is_symlink():result[str(path.relative_to(root))]='link:'+os.readlink(path);dirs.remove(d)
        for name in files:
            path=Path(current)/name;rel=str(path.relative_to(root))
            if name.startswith('.') or name.endswith(('.bsp','.pyc')):continue
            result[rel]='link:'+os.readlink(path) if path.is_symlink() else digest(path)
    if len(result)>4096:raise ValueError('Unexpected runtime contents')
    return result


def register(state,runtime,plugin):
    runtime=runtime.resolve();plugin=plugin.resolve()
    manifest=read(plugin/'manifest.json')
    if manifest.get('id') not in IDS:raise ValueError('Unsupported widget identity')
    write(state/'updates/installed.json',{'runtime':str(runtime),'plugin':str(plugin),
          'runtimeFiles':fingerprints(runtime),'pluginFiles':fingerprints(plugin),
          'version':read(runtime/'manifest.json')['version'],'registered':stamp()})


@contextmanager
def exclusive(state):
    state.mkdir(mode=0o700,parents=True,exist_ok=True)
    with (state/'install.lock').open('a') as f:
        try:fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise ValueError('Another installation is running') from None
        yield


class Services:
    def __init__(self):
        self.env={**os.environ,'XDG_RUNTIME_DIR':f'/run/user/{os.getuid()}'}
    def call(self,*args,check=True):
        return subprocess.run(['systemctl','--user',*args],env=self.env,capture_output=True,text=True,check=check,timeout=30)
    def active(self):return self.call('is-active','--quiet','omanova-worker.service',check=False).returncode==0
    def stop(self):self.call('stop','omanova-worker.service')
    def start(self):self.call('start','omanova-worker.service')
    def healthy(self,state,revision,started):
        for _ in range(60):
            try:
                s=read(state/'snapshot.json');date=datetime.fromisoformat(s['generated'].replace('Z','+00:00'))
                if self.active() and s.get('runtime',{}).get('revision')==revision and date>=started-timedelta(seconds=1):return True
            except (OSError,ValueError,KeyError,TypeError):pass
            time.sleep(1)
        return False


def preflight(state):
    managed=read(state/'updates/installed.json');runtime=Path(managed['runtime']);plugin=Path(managed['plugin'])
    alias=state/'runtime'
    if not alias.is_symlink() or alias.resolve()!=runtime:raise ValueError('Runtime changed; review installation before updating')
    config=Path.home()/'.config'
    if plugin.parent!=config/'omarchy/plugins' or plugin.name not in IDS:raise ValueError('Widget path is not managed')
    if not runtime.is_dir() or not plugin.is_dir() or plugin.is_symlink():raise ValueError('Unsupported installation layout')
    if fingerprints(runtime)!=managed['runtimeFiles'] or fingerprints(plugin)!=managed['pluginFiles']:
        raise ValueError('Local changes detected; preserve them before installing a public update')
    if (runtime/'.git').exists():
        dirty=subprocess.check_output(['git','-C',str(runtime),'status','--porcelain','--untracked-files=no'],text=True,timeout=15)
        if dirty.strip():raise ValueError('Runtime checkout has uncommitted changes')
    return managed


def unpack(blob,destination,v):
    prefix=f'omanova-{v}';seen=set();links=[];total=0
    with tarfile.open(blob,'r:gz') as archive:
        members=archive.getmembers()
        if len(members)>4096:raise ValueError('Too many archive entries')
        for m in members:
            p=PurePosixPath(m.name)
            if p.parts[0]!=prefix:raise ValueError('Unexpected archive root')
            if len(p.parts)==1:
                if not m.isdir():raise ValueError('Invalid archive root')
                continue
            rel=str(PurePosixPath(*p.parts[1:]));safe_relative(rel)
            if rel in seen:raise ValueError('Duplicate archive path')
            seen.add(rel);target=destination/rel
            if m.isdir():target.mkdir(parents=True,exist_ok=True);continue
            if m.issym():links.append((target,m.linkname));continue
            if not m.isfile() or m.mode&0o6000:raise ValueError('Unsupported archive entry')
            total+=m.size
            if total>128*1024*1024:raise ValueError('Archive expands beyond limit')
            target.parent.mkdir(parents=True,exist_ok=True)
            with archive.extractfile(m) as src,target.open('xb') as out:shutil.copyfileobj(src,out)
            target.chmod(0o755 if m.mode&0o111 else 0o644)
        for target,link in links:
            if PurePosixPath(link).is_absolute():raise ValueError('External archive link')
            resolved=(target.parent/link).resolve()
            if not resolved.is_relative_to(destination.resolve()) or not resolved.is_dir() or resolved.is_symlink():raise ValueError('Unsafe archive import link')
            if any((destination/n).is_relative_to(target) for n in seen if destination/n!=target):raise ValueError('Archive writes through link')
            target.parent.mkdir(parents=True,exist_ok=True);target.symlink_to(link)
    if read(destination/'manifest.json').get('version')!=v:raise ValueError('Archive version mismatch')
    for name in (*WIDGET_FILES,'install','setup-runtime','worker.py','requirements.txt','runtime_identity.py','update_manager.py'):
        if not (destination/name).is_file() or (destination/name).is_symlink():raise ValueError('Incomplete release')


def prepare(state,ticket,old):
    base=state/'updates/runtimes';base.mkdir(parents=True,exist_ok=True,mode=0o700)
    work=Path(tempfile.mkdtemp(prefix=ticket['version']+'-',dir=base));runtime=work/'runtime';runtime.mkdir()
    # Bound all responses; only fixed official release URLs accepted by release().
    sums=fetch(ticket['assets']['SHA256SUMS'],65536).decode('ascii')
    expected=[line.split()[0] for line in sums.splitlines() if len(line.split())==2 and line.split()[1]==ticket['name']]
    if len(expected)!=1 or not re.fullmatch('[0-9a-f]{64}',expected[0]):raise ValueError('Invalid release checksum')
    blob=fetch(ticket['assets'][ticket['name']],64*1024*1024)
    if hashlib.sha256(blob).hexdigest()!=expected[0]:raise ValueError('Release checksum mismatch')
    archive=work/'package.tar.gz';archive.write_bytes(blob);unpack(archive,runtime,ticket['version'])
    revision=fetch(ticket['assets']['SOURCE-COMMIT.txt'],128).decode('ascii').strip()
    if not re.fullmatch('[0-9a-f]{40}',revision) or (runtime/'SOURCE-COMMIT.txt').read_text().strip()!=revision:raise ValueError('Source identity mismatch')
    widget=work/'widget'
    subprocess.run(['git','clone','--quiet','--branch',ticket['tag'],f'https://github.com/{REPO}.git',str(widget)],check=True,timeout=120)
    actual=subprocess.check_output(['git','-C',str(widget),'rev-parse','HEAD'],text=True,timeout=15).strip()
    if actual!=revision:raise ValueError('Release tag/source revision mismatch')
    # Compare every archived source file against the tag, not only the widget.
    for rel,value in fingerprints(runtime).items():
        if rel=='SOURCE-COMMIT.txt':continue
        p=widget/rel
        if value.startswith('link:'):
            if not p.is_symlink() or value!='link:'+os.readlink(p):raise ValueError('Archive/tag mismatch')
        elif not p.is_file() or p.is_symlink() or digest(p)!=value:raise ValueError('Archive/tag mismatch')
    (runtime/'assets').mkdir(exist_ok=True)
    kernel=Path(old['runtime'])/'assets/de440s.bsp'
    if kernel.is_file() and digest(kernel)==KERNEL_SHA:shutil.copyfile(kernel,runtime/'assets/de440s.bsp')
    else:
        data=fetch(KERNEL_URL,34*1024*1024)
        if hashlib.sha256(data).hexdigest()!=KERNEL_SHA:raise ValueError('Ephemeris checksum mismatch')
        (runtime/'assets/de440s.bsp').write_bytes(data)
    req=(runtime/'requirements.txt').read_text().splitlines()
    if not req or any(not re.fullmatch(r'[a-zA-Z0-9_.-]+==[a-zA-Z0-9_.+-]+',s) for s in req if s.strip()):raise ValueError('Dependencies must be pinned package versions')
    subprocess.run(['uv','venv','--python','/usr/bin/python','--no-python-downloads',str(runtime/'.venv')],check=True,timeout=60)
    subprocess.run(['uv','pip','install','--python',str(runtime/'.venv/bin/python'),'-r',str(runtime/'requirements.txt')],check=True,timeout=180)
    write(runtime/'.omanova-build.json',{'revision':revision})
    # Preserve compatibility identity/bar placement; update versioned widget source.
    previous=read(Path(old['plugin'])/'manifest.json');new=read(widget/'manifest.json')
    if new.get('id')!='io.github.shaggyrs6-netizen.omanova':raise ValueError('Unexpected plugin identity')
    if previous['id']=='local.omasky':
        new['id']='local.omasky';write(widget/'manifest.json',new)
    return runtime,widget,revision


def swap_alias(state,target):
    temp=state/('runtime-update-'+str(os.getpid()))
    temp.symlink_to(target);os.replace(temp,state/'runtime')


def restore(state,services):
    path=state/'updates/journal.json';j=read(path)
    if j.get('phase')=='restored':return
    if j.get('phase')=='complete':preflight(state)
    managed=j['previous'];runtime=Path(managed['runtime']);plugin=Path(managed['plugin']);backup=Path(j['backup'])
    config=Path.home()/'.config'
    if plugin.parent!=config/'omarchy/plugins' or plugin.name not in IDS or not backup.is_relative_to(state/'updates/backups'):
        raise ValueError('Invalid recovery journal; manual review required')
    alias=state/'runtime'
    if not alias.is_symlink() or alias.resolve() not in (runtime,Path(j.get('candidate',str(runtime)))):raise ValueError('Runtime changed since update; review recovery manually')
    if not runtime.is_dir():raise ValueError('Original runtime unavailable; manual review required')
    if services.active():services.stop()
    if backup.exists():
        if plugin.exists():plugin.rename(backup.parent/'failed-widget')
        backup.rename(plugin)
    swap_alias(state,runtime);write(state/'updates/installed.json',managed)
    if j['wasActive']:services.start()
    j['phase']='restored';write(path,j)


def install(state,ticket,services=None,prepare_fn=prepare):
    services=services or Services()
    with exclusive(state):
        journal=state/'updates/journal.json'
        if journal.exists() and read(journal).get('phase') not in ('complete','restored'):
            raise ValueError('An interrupted update needs Restore previous installation first')
        previous=preflight(state)
        if version(ticket['version'])<=version(previous['version']):raise ValueError('No newer stable release; local changes are not a release update')
        runtime,widget,revision=prepare_fn(state,ticket,previous)
        # Revalidate after potentially slow downloads/environment preparation.
        assert preflight(state)==previous
        unit=Path.home()/'.config'/'systemd/user/omanova-worker.service'
        if not unit.is_file() or unit.is_symlink() or unit.read_bytes()!=(runtime/'systemd/omanova-worker.service').read_bytes():raise ValueError('Worker unit differs; use reviewed manual setup')
        plugin=Path(previous['plugin']);backup=state/'updates/backups'/runtime.parent.name/'widget';backup.parent.mkdir(parents=True,exist_ok=False,mode=0o700)
        j={'phase':'prepared','previous':previous,'backup':str(backup),'wasActive':services.active(),'candidate':str(runtime),'pid':os.getpid(),'processStart':process_start(os.getpid())}
        write(journal,j)
        try:
            if j['wasActive']:services.stop()
            with (state/'watch.lock').open('a') as lock:
                try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                except BlockingIOError:raise ValueError('Foreground worker is running; stop it before updating') from None
                j['phase']='switching';write(journal,j)
                plugin.rename(backup);widget.rename(plugin);swap_alias(state,runtime)
                register(state,runtime,plugin);j['phase']='activated';write(journal,j)
            if j['wasActive']:
                started=datetime.now(UTC);services.start()
                if not services.healthy(state,revision,started):raise ValueError('New worker did not become ready')
            j['phase']='complete';write(journal,j)
        except Exception:
            restore(state,services)
            raise
    return {'status':'installed','version':ticket['version'],'message':'Update installed. Close and reopen Observatory; reload the Omarchy shell to refresh the bar. Previous installation retained for recovery.'}


def process_start(pid):
    try:return Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()[19]
    except (OSError,IndexError):return None


def status(state):
    result={'status':'idle','message':'Check GitHub for a newer stable release. Nothing is downloaded until you ask.'}
    p=state/'updates/result.json'
    if p.exists():result=read(p)
    j=state/'updates/journal.json'
    if j.exists() and read(j).get('phase') not in ('complete','restored') and not (read(j).get('processStart') and process_start(read(j).get('pid'))==read(j).get('processStart')):
        result={'status':'recovery','message':'Update incomplete. Restore the previous installation before retrying.'}
    job=state/'updates/job.json'
    if result.get('status')=='running' and job.exists():
        owner=read(job)
        if not owner.get('start') or process_start(owner['pid'])!=owner['start']:
            result={'status':'error','message':'Update process ended before completion. Check again or inspect the local update log.'}
    return result


def dispatch(action,state,fixture=False):
    if fixture:
        return {'status':'available' if action=='check' else 'fixture','version':'0.1.6','notes':'SIMULATED release for updater UI testing.','message':'Demonstration only: no download, install, service or source change.','canInstall':action=='check'}
    if action=='status':return status(state)
    if action=='check':
        now=datetime.now(UTC);p=state/'updates/ticket.json'
        if p.exists() and timedelta(0)<=now-datetime.fromisoformat(read(p)['checked'])<timedelta(minutes=5):ticket=read(p)
        else:
            ticket=release(json.loads(fetch(API,262144)));write(p,ticket)
        installed=read((state/'runtime').resolve()/'manifest.json')['version']
        newer=version(ticket['version'])>version(installed)
        note='New stable release available.' if newer else 'You have the latest public release version. This local build may include unreleased changes.'
        try:preflight(state);managed=True
        except (OSError,ValueError,KeyError):managed=False
        return {**ticket,'status':'available' if newer else 'current','installed':installed,'canInstall':newer and managed,
                'message':note+('' if managed else ' Automatic installation needs a registered, unmodified installation.')}
    if action in ('launch','restore'):
        if status(state).get('status')=='running':raise ValueError('An update is already running')
        # One detached child survives the UI closing; install.lock serialises writes.
        p=state/'updates/ticket.json'
        if action=='launch':
            ticket=read(p)
            if not timedelta(0)<=datetime.now(UTC)-datetime.fromisoformat(ticket['checked'])<=timedelta(minutes=30):raise ValueError('Check for updates again before installing')
            preflight(state)
        write(state/'updates/result.json',{'status':'running','message':'Preparing update… Keep this session signed in. Installation runs independently of this window.'})
        log=(state/'updates/update.log').open('ab')
        try:
            child=subprocess.Popen([sys.executable,str(ROOT/'update_manager.py'),'--state',str(state),'_restore' if action=='restore' else '_install'],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True,close_fds=True)
        except OSError:
            log.close()
            write(state/'updates/result.json',{'status':'error','message':'Could not start the update process. Installation unchanged; check again later.'})
            raise
        write(state/'updates/job.json',{'pid':child.pid,'start':process_start(child.pid)})
        log.close();return status(state)
    if action=='_install':return install(state,read(state/'updates/ticket.json'))
    if action=='_restore':
        with exclusive(state):restore(state,Services())
        return {'status':'restored','message':'Previous installation restored. Close and reopen Observatory.'}
    raise ValueError('Unknown update operation')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--state',type=Path,required=True);parser.add_argument('--fixture',action='store_true');parser.add_argument('--plugin',type=Path);parser.add_argument('action',choices=('check','status','launch','restore','_install','_restore','register'));args=parser.parse_args()
    os.umask(0o077)
    try:
        if args.action=='register':
            if not args.plugin:raise ValueError('Specify widget path')
            register(args.state,ROOT,args.plugin);result={'status':'registered','message':'Update baseline recorded.'}
        else:result=dispatch(args.action,args.state,args.fixture)
    except Exception as exc:
        result={'status':'error','message':'Update failed or was refused. Existing data retained. Check the local update log or use the documented installer; no automatic retry.'}
        if isinstance(exc,ValueError):result['message']=str(exc)[:400]
        print(type(exc).__name__+': '+str(exc)[:400],file=sys.stderr)
        if args.action.startswith('_'):
            j=args.state/'updates/journal.json'
            if j.exists() and read(j).get('phase') not in ('complete','restored'):result['status']='recovery'
    if args.action.startswith('_'):write(args.state/'updates/result.json',result)
    print(json.dumps(result,ensure_ascii=False))
    return 0 if result['status'] not in ('error','recovery') else 1

if __name__=='__main__':raise SystemExit(main())
