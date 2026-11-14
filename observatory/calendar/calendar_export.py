"""Local, explicit iCalendar snapshot export. No calendar account or network access."""
import argparse
from datetime import UTC,datetime,timedelta
import hashlib
import json
import os
from pathlib import Path
import secrets
import sys

ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from astronomy import iso,utc
from worker import DEFAULT_STATE,read,write,lock
from observatory.equipment.equipment import clean_row,fixtures

LIVE_STATE=Path(os.environ.get('XDG_DATA_HOME') or Path.home()/'.local/share')/'omanova-calendar'

def allowed_state(state):
    state=state.resolve()
    return state==LIVE_STATE.resolve() or state.is_relative_to((ROOT/'.preview').resolve())

def request_source(state,payload):
    deployed=state.resolve()==LIVE_STATE.resolve()
    source=payload.get('source','live' if deployed else 'sample')
    if source not in ('sample','live') or (deployed and source!='live'):raise ValueError('Live calendar state requires real planner data')
    return source

MAX_EVENTS=50
LEADS=(0,5,15,30,60)

def bounded_text(value,limit=3000):
    # Text fields cannot inject content lines or properties; newline is escaped below.
    value=str(value or '').replace('\r\n','\n').replace('\r','\n')
    return ''.join(c for c in value if c=='\n' or ord(c)>=32 and ord(c)!=127)[:limit]

def escape(value):
    return bounded_text(value).replace('\\','\\\\').replace('\n','\\n').replace(';','\\;').replace(',','\\,')

def fold(line):
    lines=[];part='';size=0
    for char in line:
        n=len(char.encode('utf-8'))
        if size+n>75:lines.append(part);part=' ';size=1
        part+=char;size+=n
    lines.append(part)
    return '\r\n'.join(lines)

def stamp(value):return utc(value).strftime('%Y%m%dT%H%M%SZ')

def catalogue(state,source,now,live_path=None):
    error='';namespace='sample-v1'
    if source=='sample':
        stored=read(state/'samples.json',None)
        if stored is None:
            stored={'clock':iso(now),'rows':fixtures(now)};write(state/'samples.json',stored)
        now=utc(stored['clock']);generated=iso(now);rows=stored['rows']
    elif source=='live':
        data=read(live_path or DEFAULT_STATE/'planner.json',{})
        if not isinstance(data,dict):data={}
        rows=data.get('events',[]);generated=data.get('generated')
        if data.get('issues'):error='Planner reports source issues; recheck in the live Observatory. Export is blocked.'
        if not rows:error='No live planning events available. No data were downloaded.'
        namespace='live-'+hashlib.sha256(str(data.get('location_id','unknown')).encode()).hexdigest()
    else:raise ValueError('Unknown source')
    if not isinstance(rows,list) or len(rows)>3000:raise ValueError('Unexpected event catalogue')
    output=[];seen=set()
    for raw in rows:
        r=clean_row(raw)
        if not r or not r['id'] or r['id'] in seen:continue
        seen.add(r['id']);blocked='';notes=[]
        try:
            stale=not timedelta(0)<=now-utc(generated)<=timedelta(minutes=3)
            stale |= bool(r['valid_until']) and now>utc(r['valid_until'])
            if r['look'].get('time'):stale |= utc(r['look']['time'])<now-timedelta(minutes=5)
        except (ValueError,TypeError,OverflowError):stale=True
        if stale or r['visibility']=='stale':blocked='Stale prediction — refresh before exporting.'
        if utc(r['end'])<=now:blocked='This event has ended.'
        if r['kind']=='launch':blocked='Global launch schedule: local observing window/precision not established.'
        if error:blocked=error
        weather=r['conditions']['label']
        try:forecast_fresh=timedelta(0)<=now-utc(r['conditions']['fetched'])<timedelta(hours=6)
        except (ValueError,TypeError,OverflowError):forecast_fresh=False
        if not forecast_fresh:weather='Uncertain';notes.append('Forecast freshness unavailable or expired.')
        solar=r['kind']=='eclipse' and ('solar' in r['name'].casefold() or bool(r['safety']))
        geometry=r['look']['az'] is not None and r['look']['el'] is not None and r['look']['el']>0
        caution=solar or r['visibility']!='possible' or weather!='Favourable' or not r['recommended'] or not geometry
        label='Safety review' if solar else 'Visibility unconfirmed' if r['visibility']!='possible' else 'Poor conditions' if weather=='Poor' else 'Check conditions' if caution else 'Potential viewing'
        if not geometry:notes.append('Local look direction is unavailable or not above the horizon.')
        if not r['recommended']:notes.append('Underlying planner did not recommend this event; export is not a recommendation.')
        notes.extend(['Visibility: '+r['visibility']+'. Weather: '+weather+'.',r['reason']])
        if solar:notes.append('Solar safety: generic eye/binocular/telescope/camera choices do not establish safe viewing equipment. Use appropriate certified solar viewers or front-mounted solar filters for optics; check NASA safety guidance.')
        if r['safety']:notes.append(r['safety'])
        key=hashlib.sha256((namespace+'|'+r['id']).encode()).hexdigest()+'@omanova.local'
        output.append({**r,'conditions':{**r['conditions'],'label':weather},'uid':key,'blocked':blocked,'caution':caution,'label':label,'notes':[n for n in notes if n]})
    output.sort(key=lambda r:(bool(r['blocked']),r['start'],r['name']))
    return {'source':source,'generated':generated,'clock':iso(now),'error':error,'rows':output[:500],'total':len(output)}

def render(rows,now,source,lead=0):
    if type(lead) is not int or lead not in LEADS:raise ValueError('Choose a supported reminder')
    if not rows or len(rows)>MAX_EVENTS:raise ValueError('Select between one and 50 events')
    lines=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//OMANOVA//Observing Snapshot//EN','CALSCALE:GREGORIAN']
    for r in rows:
        if r['blocked']:raise ValueError('Refresh stale or unsupported events before exporting')
        title=('SIMULATED · ' if source=='sample' else '')+r['label']+' · '+r['name']
        look=r['look'];direction='Look: '+(look.get('direction') or 'unknown direction')
        if look.get('az') is not None:direction+=' ('+str(round(look['az'],1))+'° azimuth)'
        if look.get('el') is not None:direction+=', '+str(round(look['el'],1))+'° altitude'
        note='\n'.join((('SIMULATED EXAMPLE — not a real prediction.\n' if source=='sample' else '')+'OMANOVA observing window. Visibility is not guaranteed.',
                        *r['notes'],direction,'Source: '+(r['source'] or 'Not supplied'),
                        'One-off snapshot. Recheck current times, weather, horizon and safety in OMANOVA before observing. This export will not update or cancel itself.',
                        'Times are UTC; your calendar displays its selected time zone. Location name and coordinates are omitted.'))
        alarm=lead>0 and utc(r['start'])-timedelta(minutes=lead)>now
        if lead and not alarm:note+='\nReminder omitted: trigger time is already past.'
        lines+=['BEGIN:VEVENT','UID:'+r['uid'],'DTSTAMP:'+now.strftime('%Y%m%dT%H%M%SZ'),'DTSTART:'+stamp(r['start']),'DTEND:'+stamp(r['end']),
                'SUMMARY:'+escape(title),'DESCRIPTION:'+escape(note),'STATUS:TENTATIVE','CLASS:PRIVATE','TRANSP:TRANSPARENT']
        # No URL property: third-party strings stay escaped within DESCRIPTION.
        if alarm:lines+=['BEGIN:VALARM','ACTION:DISPLAY','TRIGGER:-PT'+str(lead)+'M','DESCRIPTION:'+escape(title),'END:VALARM']
        lines+=['END:VEVENT']
    lines+=['END:VCALENDAR']
    return ('\r\n'.join(fold(line) for line in lines)+'\r\n').encode('utf-8')

def export(state,payload,now=None):
    now=now or datetime.now(UTC)
    source=request_source(state,payload);ids=payload.get('ids');lead=payload.get('lead',0)
    if not isinstance(ids,list) or not 1<=len(ids)<=MAX_EVENTS or any(not isinstance(i,str) for i in ids) or len(set(ids))!=len(ids):raise ValueError('Select one to 50 different events')
    if type(payload.get('includeCaution',False)) is not bool:raise ValueError('Invalid caution choice')
    # Re-read and recheck at export time. UI data is never trusted as event content.
    data=catalogue(state,source,now);found={r['id']:r for r in data['rows']}
    if any(i not in found for i in ids):raise ValueError('Selection changed; refresh and select again')
    rows=[found[i] for i in ids]
    if any(r['caution'] for r in rows) and not payload.get('includeCaution',False):raise ValueError('Explicitly include uncertain or poor-condition events first')
    content=render(rows,now,source,lead)
    target=state/'exports';target.mkdir(mode=0o700,exist_ok=True)
    name='omanova-'+('SIMULATED-' if source=='sample' else '')+now.strftime('%Y%m%dT%H%M%SZ')+'-'+secrets.token_hex(4)+'.ics'
    path=target/name
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'wb') as f:f.write(content);f.flush();os.fsync(f.fileno())
    receipt={'path':str(path),'count':len(rows),'source':source,'lead':lead,'created':iso(now),'sha256':hashlib.sha256(content).hexdigest()}
    write(state/'receipt.json',receipt)
    return receipt

def run(state,action,payload,now=None):
    now=now or datetime.now(UTC)
    with lock(state):
        source=request_source(state,payload)
        if action=='export':export(state,payload,now)
        elif action not in ('init','refresh'):raise ValueError('Unknown action')
        write(state/'view.json',catalogue(state,source,now))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--state',type=Path,required=True);parser.add_argument('action',choices=('init','refresh','export'));args=parser.parse_args()
    state=args.state.resolve()
    if not allowed_state(state):raise ValueError('Use the dedicated calendar state or checkout preview directory')
    os.umask(0o077);payload={}
    if args.action!='init':
        raw=sys.stdin.buffer.readline(16385)
        if len(raw)>16384 or not raw.endswith(b'\n'):raise ValueError('Expected one bounded JSON request')
        payload=json.loads(raw)
        if not isinstance(payload,dict):raise ValueError('Expected an export request')
    run(state,args.action,payload)
    print('Local calendar catalogue updated')

if __name__=='__main__':
    try:main()
    except (ValueError,OSError,KeyError,TypeError,AttributeError,OverflowError):raise SystemExit('Calendar export could not update. Refresh and check selected events, caution choice and reminder.')
