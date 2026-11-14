"""Isolated launch-following trial. No observing coordinates, live worker or services."""
import argparse
from copy import deepcopy
from datetime import datetime,timedelta,timezone
from html import escape
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
from uuid import UUID

ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from worker import read,write,lock,get_json
from observatory.events.launches import normalise,BASE,FEED,stream_url
from astronomy import utc,iso
UTC=timezone.utc
MAX_FAVOURITES=5
DEFAULT={'favourites':[],'downloads':False,'alerts':False,'delayAlerts':True,'statusAlerts':True}


def prefs(raw):
    out=deepcopy(DEFAULT)
    if not isinstance(raw,dict) or set(raw)-set(DEFAULT):raise ValueError('Invalid follow settings')
    for k in DEFAULT:
        if k=='favourites':
            rows=raw.get(k,[])
            if not isinstance(rows,list) or len(rows)>MAX_FAVOURITES:raise ValueError('Follow up to five launches in this preview')
            try:out[k]=list(dict.fromkeys(str(UUID(v)) for v in rows))
            except (TypeError,ValueError,AttributeError):raise ValueError('Invalid launch identifier') from None
        else:
            v=raw.get(k,DEFAULT[k])
            if type(v) is not bool:raise ValueError('Follow controls require true or false')
            out[k]=v
    return out


def fingerprint(row):
    fields=['net','precision','status','statusId','windowStart','windowEnd']
    return hashlib.sha256(json.dumps({k:row.get(k) for k in fields},sort_keys=True).encode()).hexdigest()


def time_label(row):
    net=row.get('net');precision=row.get('precision')
    if not net:return 'time not announced'
    if precision in ('SEC','MIN'):return utc(net).astimezone().strftime('%a %d %b %H:%M %Z')+' / '+utc(net).strftime('%H:%M UTC')
    if precision=='HR':return 'around '+utc(net).astimezone().strftime('%a %d %b %H:%M %Z')+' (hour estimate)'
    return {'DAY':net[:10]+' UTC, time TBD','MTH':net[:7]+', month only','YR':net[:4]+', year only'}.get(precision,'time unconfirmed')


def changes(old,new):
    if new.get('statusId') in (3,4,6,7):return []
    result=[];status=new.get('status','').casefold();previous=old.get('status','').casefold()
    if status!=previous:
        if re.match(r'^scrub(?:bed)?\b',status):result.append(('status','Source reports scrub: '+new['status']))
        elif re.match(r'^(?:cancelled|canceled|cancellation)\b',status):result.append(('status','Source reports cancellation: '+new['status']))
        elif new.get('statusId')==5 or status=='hold':result.append(('status','Source reports hold (not a confirmed scrub)'))
    if old.get('net')!=new.get('net') or old.get('precision')!=new.get('precision'):
        precise=old.get('precision') in ('SEC','MIN') and new.get('precision') in ('SEC','MIN') and old.get('net') and new.get('net')
        later=precise and utc(new['net'])>utc(old['net'])
        result.append(('delay' if later else 'schedule',('Delayed' if later else 'Schedule changed')+': '+time_label(old)+' → '+time_label(new)))
    return result


def notify(event,sample,send=subprocess.run):
    title=escape(('[Preview · simulated] ' if sample else '[Preview] ')+event['name']+' · schedule update')
    body='\n'.join(event['messages'])+'\nLaunch schedule only; local visibility unconfirmed.'
    try:send(['/usr/bin/notify-send','--app-name=OMANOVA launch preview','--urgency=normal','--expire-time=12000','--',title,escape(body)],check=True,capture_output=True,timeout=5)
    except (OSError,subprocess.SubprocessError):return False
    return True


def apply_snapshot(state,rows,fetched,now,send=None,sample=False,deliver=True):
    """Advance baselines even with alerts off. Only fresh, forward observations notify."""
    p=prefs(state['prefs']);history=state.setdefault('history',[]);baselines=state.setdefault('baseline',{})
    pending=state.setdefault('pending',[])
    for row in rows:
        if row['id'] not in p['favourites']:continue
        previous=baselines.get(row['id']);fp=fingerprint(row)
        if previous and utc(fetched)<=utc(previous['fetched']):continue
        needs=state.setdefault('needsBaseline',[])
        if row['id'] in needs:
            if not timedelta(0)<=now-utc(fetched)<=timedelta(minutes=30):continue
            needs.remove(row['id']);previous=None
        baselines[row['id']]={'row':row,'fetched':fetched,'fingerprint':fp}
        if not previous or fp==previous['fingerprint']:continue
        delta=changes(previous['row'],row)
        if not delta:continue
        fresh=timedelta(0)<=now-utc(fetched)<=timedelta(minutes=30) and timedelta(0)<utc(fetched)-utc(previous['fetched'])<=timedelta(hours=2)
        selected=[message for kind,message in delta if (kind in ('delay','schedule') and p['delayAlerts']) or (kind=='status' and p['statusAlerts'])]
        event={'id':hashlib.sha256((row['id']+fetched+fp).encode()).hexdigest(),'launch':row['id'],'name':row['name'],
               'messages':[message for _,message in delta],'at':fetched,'delivery':'History only · alerts off or type disabled' if not p['alerts'] or not selected else 'History only · monitoring gap/stale observation' if not fresh else 'Pending'}
        history.insert(0,event)
        if p['alerts'] and selected and fresh:pending.append({**event,'messages':selected,'attempts':0})
    state['history']=history[:100]
    if not p['alerts']:pending.clear()
    if deliver:deliver_pending(state,now,send,sample)


def deliver_pending(state,now,send,sample):
    keep=[]
    for event in state.get('pending',[]):
        if event['launch'] not in state['prefs']['favourites']:continue
        if now-utc(event['at'])>timedelta(minutes=30):
            status='Not sent · update expired'
        elif event['attempts']>=3:
            status='Not sent · notification delivery failed'
        else:
            ok=(send or notify)(event,sample);event['attempts']+=1
            status='Sent' if ok else 'Retry pending · desktop notification failed'
            if not ok:keep.append(event)
        for entry in state.get('history',[]):
            if entry['id']==event['id']:entry['delivery']=status
    state['pending']=keep


def fixtures(state,scenario,now):
    rows=deepcopy(state['sampleBase']);row=rows[0]
    if scenario=='delay':row['net']=iso(utc(row['net'])+timedelta(minutes=40));row['windowStart']=row['net'];row['windowEnd']=iso(utc(row['net'])+timedelta(hours=1))
    elif scenario=='hold':row['status']='Hold';row['statusId']=5
    elif scenario=='scrub':row['status']='Scrubbed — explicit sample report';row['statusId']=None
    elif scenario=='cancel':row['status']='Cancelled — explicit sample report';row['statusId']=None
    elif scenario=='coarse':row['precision']='DAY';row['net']=iso((utc(row['net'])+timedelta(days=1)).replace(hour=0,minute=0,second=0))
    elif scenario=='missing':rows=rows[1:]
    elif scenario!='original':raise ValueError('Unknown demonstration')
    # Monotonic sample observations allow repeatable tests without changing system time.
    last=utc(state.get('fetched') or iso(now));fetched=iso(max(now,last+timedelta(seconds=1)))
    return rows,fetched,utc(fetched)


def initialise(directory,sample,now):
    state=read(directory/'state.json',None)
    if state is None and (directory/'state.json').exists():raise ValueError('Existing preview state is unreadable; keep it for inspection')
    if state is None:
        state={'prefs':deepcopy(DEFAULT),'rows':[],'baseline':{},'history':[],'pending':[],'fetched':None,'attempts':{},'error':''}
        if sample:
            source=read(ROOT/'observatory/events/launch-fixture.json',{});rows=normalise(source)
            for i,row in enumerate(rows):
                row.update(net=iso(now+timedelta(hours=3+i*12)),windowStart=iso(now+timedelta(hours=3+i*12)),windowEnd=iso(now+timedelta(hours=4+i*12)))
                row['stream']='https://www.youtube.com/' if i==0 else None
            state.update(rows=rows,sampleBase=deepcopy(rows),fetched=iso(now))
    state['prefs']=prefs(state['prefs']);return state


def request_json(state,key,url,now,fetch):
    attempts=state.setdefault('attempts',{});cached=state.setdefault('cache',{})
    last=attempts.get(key)
    interval=timedelta(minutes=15) if key=='upcoming' else timedelta(hours=1)
    if last and now-utc(last)<interval:return cached.get(key),False
    recent=[t for t in state.get('requestHistory',[]) if timedelta(0)<=now-utc(t)<timedelta(hours=1)]
    state['requestHistory']=recent
    if len(recent)>=9:raise ValueError('Preview request budget reached; cached data retained')
    attempts[key]=iso(now);state['requestHistory'].append(iso(now))
    payload=fetch(url)
    rows=normalise(payload if key=='upcoming' else {'results':[payload]})
    cached[key]={'rows':rows,'fetched':iso(now)}
    return cached[key],True


def refresh(state,now,fetch=get_json,send=None):
    if not state['prefs']['downloads']:raise ValueError('Enable launch downloads before checking the live schedule')
    if state.get('blockedUntil') and now<utc(state['blockedUntil']):raise ValueError('Provider cooldown active; cached schedule retained')
    records={row['id']:row for row in state.get('rows',[])};timestamps=state.setdefault('observed',{})
    errors=[]
    try:
        cache,new=request_json(state,'upcoming',FEED,now,fetch)
        if cache:
            for row in cache['rows']:records[row['id']]=row;timestamps[row['id']]=cache['fetched']
        for launch in state['prefs']['favourites']:
            seen=timestamps.get(launch)
            if seen and timedelta(0)<=now-utc(seen)<timedelta(hours=1):continue
            detail,new=request_json(state,launch,BASE+launch+'/?mode=detailed',now,fetch)
            if detail:
                for row in detail['rows']:records[row['id']]=row;timestamps[row['id']]=detail['fetched']
    except (OSError,ValueError,TypeError,KeyError) as exc:
        errors.append('Provider unavailable, rate-limited or invalid response. Cached rows kept; requests paused at least 15 minutes (one hour after rate limiting).')
        state['blockedUntil']=iso(now+timedelta(hours=1) if getattr(exc,'code',None)==429 else now+timedelta(minutes=15))
    favourite_rows=[row for key,row in records.items() if key in state['prefs']['favourites']]
    others=[row for key,row in records.items() if key not in state['prefs']['favourites']]
    state['rows']=favourite_rows+others[-(100-len(favourite_rows)):]
    state['attempts']={k:v for k,v in state.get('attempts',{}).items() if now-utc(v)<timedelta(hours=1)}
    keep=set(state['prefs']['favourites'])|{'upcoming'}
    state['cache']={k:v for k,v in state.get('cache',{}).items() if k in keep}
    state['observed']={k:v for k,v in timestamps.items() if k in {r['id'] for r in state['rows']}}
    for row in state['rows']:
        if row['id'] in timestamps:apply_snapshot(state,[row],timestamps[row['id']],now,send,sample=False,deliver=False)
    deliver_pending(state,now,send,False)
    state['fetched']=max(timestamps.values(),default=state.get('fetched'));state['error']=' '.join(errors)


def view(state,sample,now):
    p=prefs(state['prefs']);rows=[]
    present={r['id'] for r in state['rows']}
    displayed=state['rows']+[v['row'] for k,v in state.get('baseline',{}).items() if k in p['favourites'] and k not in present]
    for row in displayed:
        age=now-utc(state.get('observed',{}).get(row['id']) or state.get('fetched') or iso(now-timedelta(days=30)))
        rows.append({**row,'favourite':row['id'] in p['favourites'],'timeLabel':time_label(row),
                     'available':row['id'] in present,'fresh':row['id'] in present and (sample or timedelta(0)<=age<=timedelta(minutes=30)),'stream':stream_url(row.get('stream'))})
    return {'sample':sample,'prefs':p,'rows':rows,'history':state.get('history',[]),'fetched':state.get('fetched'),
            'error':state.get('error',''),'pending':len(state.get('pending',[]))}


def command(directory,sample,action,payload,now=None,send=None,fetch=get_json):
    now=now or datetime.now(UTC)
    with lock(directory):
        state=initialise(directory,sample,now)
        if action=='init':
            state['prefs']['alerts']=False;state['prefs']['downloads']=False;state['pending']=[]
            if not sample:state['needsBaseline']=list(state['prefs']['favourites'])
        elif action=='preferences':
            enabled_before=state['prefs']['alerts']
            state['prefs']=prefs(payload)
            if not sample and state['prefs']['alerts'] and not enabled_before:state['needsBaseline']=list(state['prefs']['favourites'])
            if not state['prefs']['alerts']:state['pending']=[]
        elif action=='favourite':
            key=str(UUID(payload['id']));p=state['prefs'];add=payload['on']
            if type(add) is not bool:raise ValueError('Choose a favourite state')
            if add and key not in p['favourites']:
                if len(p['favourites'])>=MAX_FAVOURITES:raise ValueError('Follow up to five launches in this preview')
                row=next((r for r in state['rows'] if r['id']==key),None)
                if not row:raise ValueError('Choose a launch in the displayed schedule')
                p['favourites'].append(key);state['needsBaseline']=[x for x in state.get('needsBaseline',[]) if x!=key];fetched=state.get('observed',{}).get(key) or state.get('fetched') or iso(now)
                state['baseline'][key]={'row':row,'fetched':fetched,'fingerprint':fingerprint(row)}
            elif not add:
                p['favourites']=[v for v in p['favourites'] if v!=key];state['baseline'].pop(key,None);state['pending']=[e for e in state['pending'] if e['launch']!=key]
        elif action=='refresh':refresh(state,now,fetch,send)
        elif action=='simulate':
            if not sample:raise ValueError('Simulations are available only for sample missions')
            if payload['scenario']=='outage':state['error']='Simulated provider outage · cached favourites kept';state['pending']=[]
            else:
                rows,fetched,now=fixtures(state,payload['scenario'],now)
                apply_snapshot(state,rows,fetched,now,send,True);state.update(rows=rows,fetched=fetched,error='')
        elif action=='tick':
            if not sample and state['prefs']['downloads']:refresh(state,now,fetch,send)
            elif state['prefs']['alerts']:deliver_pending(state,now,send,sample)
        else:raise ValueError('Unknown follow command')
        write(directory/'state.json',state);write(directory/'view.json',view(state,sample,now))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);parser.add_argument('--mode',choices=('sample','live'),default='sample');parser.add_argument('action',choices=('init','preferences','favourite','refresh','simulate','tick'));args=parser.parse_args()
    base=args.root.resolve()
    if not base.is_relative_to((ROOT/'.preview').resolve()):raise ValueError('Use a preview directory inside this checkout')
    os.umask(0o077);payload={}
    if args.action in ('preferences','favourite','simulate'):
        raw=sys.stdin.buffer.readline(8193)
        if len(raw)>8192 or not raw.endswith(b'\n'):raise ValueError('Expected one bounded JSON request')
        payload=json.loads(raw)
    command(base/args.mode,args.mode=='sample',args.action,payload)
    print('Updated launch-follow preview')

if __name__=='__main__':
    try:main()
    except (OSError,ValueError,TypeError,KeyError,AttributeError):raise SystemExit('Could not update preview. Check settings, request limits and local files.')
