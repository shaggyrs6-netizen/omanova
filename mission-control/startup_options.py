"""Opt-in XDG login entry. Preference changes go through Omarchy Control."""
import json,os,subprocess
from pathlib import Path
ENTRY='omanova-mission-control.desktop'
ROOT=Path(__file__).resolve().parent


def entry_path():return Path(os.environ.get('XDG_CONFIG_HOME') or Path.home()/'.config')/'autostart'/ENTRY

def command():
 p=str(ROOT/'bin/wallpaper')
 if any(x in p for x in '\n\r'):raise ValueError('Unsupported install path')
 p=p.replace('\\','\\\\').replace('"','\\"').replace('`','\\`').replace('$','\\$').replace('%','%%')
 return f'"{p}" login'

def content():
 return '[Desktop Entry]\nType=Application\nName=OMANOVA Mission Control wallpaper\nComment=Optional live desktop; restore from its control window\nExec='+command()+'\nTryExec=/usr/bin/python3\nOnlyShowIn=Hyprland;\nHidden=true\nX-OMANOVA-Managed=mission-control-login-v1\n'

def verify_path(p):
 for parent in (p.parent,p.parent.parent):
  if parent.is_symlink():raise ValueError('Linked startup directory: no changes made')
 if p.is_symlink():raise ValueError('Linked startup entry: no changes made')
 if p.exists():
  if not p.is_file() or p.stat().st_uid!=os.getuid():raise ValueError('Unmanaged startup entry: no changes made')
  # Refuse a same-name custom entry, preserving all its contents.
  text=p.read_text();fields={}
  group=''
  for line in text.splitlines():
   if line.startswith('['):group=line
   if group=='[Desktop Entry]' and '=' in line:
    k,v=line.split('=',1)
    if k in fields:raise ValueError('Duplicate startup fields: review manually')
    fields[k]=v
  if fields.get('X-OMANOVA-Managed')!='mission-control-login-v1' or fields.get('Exec')!=command() or fields.get('Type')!='Application' or fields.get('OnlyShowIn')!='Hyprland;':raise ValueError('Startup entry differs; preserve it and review manually')
  return fields
 return None

def status():
 p=entry_path();fields=verify_path(p)
 if fields is None:return {'enabled':False,'available':True,'prepared':False,'message':'Login startup is off. Enabling creates a separate Mission Control entry.'}
 enabled=fields.get('Hidden','false').lower()!='true' and fields.get('X-GNOME-Autostart-enabled','true').lower()!='false'
 return {'enabled':enabled,'available':True,'prepared':True,'message':'Login startup '+('on' if enabled else 'off')+'. Your OMANOVA worker setting is unchanged.'}

def control(args):
 result=subprocess.run(['omarchy-control',*args,'--json','--api-version','1'],capture_output=True,text=True,timeout=25)
 try:data=json.loads(result.stdout)
 except ValueError:raise ValueError('Startup control returned an unreadable result') from None
 if result.returncode or not data.get('ok'):raise ValueError('Omarchy Control refused the startup change; existing settings retained')
 return data

def change(enabled):
 p=entry_path();fields=verify_path(p)
 if not enabled and fields is None:return status()
 if fields is None:
  p.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
  with p.open('x') as f:f.write(content())
 action='enable' if enabled else 'disable'
 control(['startup',action,ENTRY,'--dry-run'])
 result=control(['startup',action,ENTRY])
 if not result.get('verified'):raise ValueError('Startup change was not verified; inspect it before retrying')
 actual=status()
 if actual['enabled']!=enabled:raise ValueError('Startup readback did not match; inspect before retrying')
 # Native provider verifies a preference, not that next-login launch has occurred.
 return {**actual,'verifiedPreference':True,'loginLaunchTested':False}
