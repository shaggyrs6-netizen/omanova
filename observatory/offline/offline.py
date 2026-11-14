"""Immutable local night guides; reopening a guide never reads live sources."""
import argparse
from copy import deepcopy
from datetime import UTC,date,datetime,time,timedelta
import html
import json
import os
from pathlib import Path
import re
import secrets
import sys
from zoneinfo import ZoneInfo,ZoneInfoNotFoundError
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from astronomy import iso,utc
from worker import DEFAULT_STATE,read,write,lock
from observatory.equipment.equipment import clean_row,fixtures,rule
LABELS={'eye':'Naked eye','binoculars':'Binoculars','telescope':'Telescope','camera':'Camera'}
ID=re.compile(r'^\d{8}T\d{6}Z-[0-9a-f]{8}$')


def desktop_zone():
    candidates=[os.environ.get('TZ','')]
    path=str(Path('/etc/localtime').resolve())
    if '/zoneinfo/' in path:candidates.append(path.split('/zoneinfo/',1)[1])
    for name in candidates:
        try:ZoneInfo(name);return name
        except (ValueError,ZoneInfoNotFoundError):pass
    return 'UTC'


def night_window(night,zone):
    if not isinstance(night,str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}',night):raise ValueError('Use YYYY-MM-DD')
    d=date.fromisoformat(night);tz=ZoneInfo(zone)
    # Noon-to-noon intentionally includes early winter evenings and next morning.
    return datetime.combine(d,time(12),tz).astimezone(UTC),datetime.combine(d+timedelta(days=1),time(12),tz).astimezone(UTC)


def display(value,zone):return utc(value).astimezone(ZoneInfo(zone)).strftime('%a %d %b · %H:%M %Z (%z)')


def source_data(state,source,now,live_path=None):
    issues=[]
    if source=='sample':
        stored=read(state/'samples.json',None)
        if stored is None:
            clock=now
            rows=fixtures(clock)
            for r in rows:r['look']['time']=iso(utc(r['start'])+(utc(r['end'])-utc(r['start']))/2)
            stored={'clock':iso(clock),'rows':rows};write(state/'samples.json',stored)
        return stored['rows'],stored['clock'],utc(stored['clock']),issues
    if source!='live':raise ValueError('Choose sample or live data')
    data=read(live_path or DEFAULT_STATE/'planner.json',{})
    if not isinstance(data,dict):data={}
    rows=data.get('events',[])
    if not isinstance(rows,list) or len(rows)>3000:raise ValueError('Unexpected planning catalogue')
    if data.get('issues'):issues.append('Planner reports source issues. Saved guidance is incomplete; recheck in OMANOVA.')
    if not rows:issues.append('No planner events available. No data were downloaded.')
    return rows,data.get('generated'),now,issues


def prepare(state,request,now,live_path=None):
    source=request.get('source','sample');zone=request.get('zone') or desktop_zone()
    ZoneInfo(zone)
    raw,generated,clock,issues=source_data(state,source,now,live_path)
    d=clock.astimezone(ZoneInfo(zone))
    night=request.get('night') or (d.date()-timedelta(days=d.hour<12)).isoformat()
    start,end=night_window(night,zone)
    try:source_stale=not timedelta(0)<=clock-utc(generated)<=timedelta(minutes=3)
    except (ValueError,TypeError,OverflowError):source_stale=True
    rows=[];seen=set()
    for original in raw:
        r=clean_row(original)
        if not r or not r['id'] or r['id'] in seen:continue
        seen.add(r['id'])
        if utc(r['end'])<=start or utc(r['start'])>=end:continue
        r['segmentStart']=iso(max(start,utc(r['start'])));r['segmentEnd']=iso(min(end,utc(r['end'])))
        r['segmentNote']='Guide segment of a longer source window.' if r['segmentStart']!=iso(utc(r['start'])) or r['segmentEnd']!=iso(utc(r['end'])) else ''
        expiries=[clock+timedelta(hours=2)]
        stale=source_stale or r['visibility']=='stale'
        try:
            if r['look']['time']:stale |= utc(r['look']['time'])<clock-timedelta(minutes=5)
        except (ValueError,TypeError,OverflowError):pass
        if r['valid_until']:
            try:expiries.append(utc(r['valid_until']));stale |= utc(r['valid_until'])<=clock
            except (ValueError,TypeError,OverflowError):stale=True
        r['recheckAt']=iso(min(expiries));r['staleAtCapture']=stale;r['sourceIssues']=bool(issues)
        r['sourceGenerated']=generated if isinstance(generated,str) else ''
        r['capturedAt']=iso(clock)
        options,sky,explanation=rule(r)
        r['equipment']=[LABELS[k] for k in options or []];r['equipmentNote']=explanation;r['skyRule']=sky
        r['solar']=r['kind']=='eclipse' and ('solar' in r['name'].casefold() or bool(r['safety']))
        if r['solar']:r['equipment']=[];r['equipmentNote']='Solar safety review required. Ordinary equipment choices do not establish safe solar filters for eyes or optics.'
        r['lookUsable']=False
        try:r['lookUsable']=r['look']['az'] is not None and r['look']['el'] is not None and r['look']['el']>0 and utc(r['segmentStart'])<=utc(r['look']['time'])<=utc(r['segmentEnd'])
        except (ValueError,TypeError,OverflowError):pass
        r['unsupported']='Global launch schedule has no established local viewing window.' if r['kind']=='launch' else ''
        r['weatherExpires']=''
        try:r['weatherExpires']=iso(utc(r['conditions']['fetched'])+timedelta(hours=6))
        except (ValueError,TypeError,OverflowError):pass
        rows.append(r)
    rows.sort(key=lambda r:(r['segmentStart'],r['name'],r['id']))
    return {'schema':1,'source':source,'night':night,'zone':zone,'windowStart':iso(start),'windowEnd':iso(end),'capturedAt':iso(clock),
            'sampleClock':iso(clock) if source=='sample' else '', 'issues':issues,'rows':rows[:300],'available':len(rows)}


def row_status(row,now):
    try:
        if now<utc(row['capturedAt']):return 'Clock mismatch — saved time is in the future'
        if utc(row['segmentEnd'])<=now:return 'Ended — saved record only'
        if row['staleAtCapture']:return 'Stale when captured — inspect only'
        if row['sourceIssues']:return 'Incomplete when captured — recheck sources'
        if now>=utc(row['recheckAt']):return 'Saved timing aged — recheck needed'
    except (ValueError,TypeError,KeyError,OverflowError):return 'Timing freshness unknown — inspect only'
    return 'Saved timing snapshot — not a live prediction'


def weather_status(row,now):
    fetched=row.get('conditions',{}).get('fetched');expiry=row.get('weatherExpires')
    try:
        if now<utc(fetched):return 'Forecast clock mismatch — do not rely on it'
        if now>=utc(expiry):return 'Saved weather stale — recheck needed'
    except (ValueError,TypeError,OverflowError):return 'Weather freshness unknown'
    return 'Saved forecast only — local conditions can differ'


def direction(row,zone):
    if not row.get('lookUsable'):return 'Direction unavailable for this night segment; no position has been extrapolated.'
    p=row['look'];return f"Look {p['direction'] or 'towards azimuth'} · {p['az']:.1f}° azimuth · {p['el']:.1f}° up · around {display(p['time'],zone)}"


def view(deck,now):
    out=deepcopy(deck)
    for r in out['rows']:
        r['status']=row_status(r,now);r['weatherStatus']=weather_status(r,now)
        r['when']=display(r['segmentStart'],out['zone'])+' — '+display(r['segmentEnd'],out['zone'])
        r['directionText']=direction(r,out['zone'])
    out['checkedAt']=iso(now)
    return out


def load_saved(state,guide):
    if not isinstance(guide,str) or not ID.fullmatch(guide):raise ValueError('Choose a saved guide')
    path=state/'guides'/guide/'deck.json';d=read(path,None)
    if not isinstance(d,dict) or d.get('schema')!=1 or not isinstance(d.get('rows'),list) or len(d['rows'])>50:raise ValueError('Saved guide unavailable; keep it for inspection')
    night_window(d['night'],d['zone']);utc(d['capturedAt'])
    return d


def saved_list(state):
    root=state/'guides'
    if not root.exists():return []
    result=[]
    for p in sorted(root.iterdir(),reverse=True):
        if len(result)>=50:break
        if not ID.fullmatch(p.name):continue
        try:
            d=load_saved(state,p.name);result.append({'id':p.name,'night':d['night'],'zone':d['zone'],'source':d['source'],'count':len(d['rows']),'savedAt':d['savedAt']})
        except (ValueError,OSError,KeyError,TypeError,ZoneInfoNotFoundError):continue
    return result


def save(state,request,now):
    deck=prepare(state,request,now);ids=request.get('ids')
    if not isinstance(ids,list) or not 1<=len(ids)<=50 or any(not isinstance(i,str) for i in ids) or len(ids)!=len(set(ids)):raise ValueError('Select one to 50 different cards')
    rows={r['id']:r for r in deck['rows']}
    if any(i not in rows or rows[i]['unsupported'] for i in ids):raise ValueError('Refresh and select available cards')
    chosen=[rows[i] for i in ids]
    if any(r['staleAtCapture'] or r['sourceIssues'] for r in chosen) and request.get('includeStale') is not True:raise ValueError('Explicitly include stale/incomplete records first')
    deck['rows']=chosen;deck['available']=len(chosen);deck['savedAt']=iso(now)
    guide=now.strftime('%Y%m%dT%H%M%SZ')+'-'+secrets.token_hex(4)
    folder=state/'guides'/guide;folder.mkdir(parents=True,mode=0o700,exist_ok=False)
    write(folder/'deck.json',deck)
    with (folder/'guide.html').open('x',encoding='utf-8') as f:f.write(render_html(deck,now))
    os.chmod(folder/'guide.html',0o600)
    return guide,deck


def render_html(deck,now):
    e=lambda v:html.escape(str(v or ''),quote=True)
    d=view(deck,now);cards=[]
    for r in d['rows']:
        attr=f'data-captured="{e(r["capturedAt"])}" data-recheck="{e(r["recheckAt"])}" data-end="{e(r["segmentEnd"])}" data-stale="{int(r["staleAtCapture"])}" data-issue="{int(r["sourceIssues"])}" data-fetched="{e(r["conditions"]["fetched"])}" data-weather="{e(r["weatherExpires"])}"'
        cards.append(f'''<article {attr}><p class="tag">{e(r['kind'].upper())} · {e(r['visibility'])} · {'Safety review' if r['solar'] else 'Visibility not guaranteed'}</p><h2>{e(r['name'])}</h2>
<p class="status">{e(r['status'])}</p><p><b>When:</b> {e(r['when'])}<br>UTC: {e(r['segmentStart'])} — {e(r['segmentEnd'])}<br>{e(r['segmentNote'])}</p>
<p><b>Where to look:</b> {e(r['directionText'])}</p><p><b>Equipment:</b> {e(', '.join(r['equipment']) or 'Capability unknown / review required')}<br>{e(r['equipmentNote'])}</p>
<p><b>Weather at capture:</b> {e(r['conditions']['label'])} · <span class="weather-status">{e(r['weatherStatus'])}</span><br>Forecast fetched: {e(r['conditions']['fetched'] or 'unknown')}; expires: {e(r['weatherExpires'] or 'unknown')}</p>
<p>Timing source checked: {e(r['sourceGenerated'] or 'unknown')}. Recheck no later than {e(r['recheckAt'])} (conservative two-hour snapshot limit, or earlier source expiry).</p>
<p>{e(r['reason'])}</p><p class="warning">{e(r['safety'])}</p><p class="source">Source reference (not fetched offline): {e(r['source'] or 'not supplied')}</p></article>''')
    script='''function refresh(){const now=Date.now();document.querySelectorAll('article').forEach(a=>{const p=a.dataset,cap=Date.parse(p.captured),end=Date.parse(p.end),check=Date.parse(p.recheck);let s='Saved timing snapshot — not a live prediction';if(!Number.isFinite(cap)||!Number.isFinite(check)||!Number.isFinite(end))s='Timing freshness unknown — inspect only';else if(now<cap)s='Clock mismatch — saved time is in the future';else if(now>=end)s='Ended — saved record only';else if(p.stale==='1')s='Stale when captured — inspect only';else if(p.issue==='1')s='Incomplete when captured — recheck sources';else if(now>=check)s='Saved timing aged — recheck needed';a.querySelector('.status').textContent=s;const f=Date.parse(p.fetched),w=Date.parse(p.weather);a.querySelector('.weather-status').textContent=!Number.isFinite(f)||!Number.isFinite(w)?'Weather freshness unknown':now<f?'Forecast clock mismatch — do not rely on it':now>=w?'Saved weather stale — recheck needed':'Saved forecast only — local conditions can differ';});}refresh();setInterval(refresh,30000);'''
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>OMANOVA · {e(d['night'])} observing guide</title>
<style>body{{background:#0a1220;color:#eef5ff;font:16px/1.55 system-ui,sans-serif;max-width:980px;margin:auto;padding:28px}}article{{background:#142137;border:1px solid #3f5872;border-radius:12px;padding:22px;margin:20px 0;break-inside:avoid}}h1,h2{{line-height:1.2}}.tag,.status{{color:#77e3df;font-weight:bold}}.warning,.weather-status,.status{{color:#ffcf8b}}.source{{overflow-wrap:anywhere;color:#afc0d5}}@media print{{body,article{{background:white;color:black}}article{{border:1px solid #777}}.tag,.status,.warning,.weather-status,.source{{color:black}}}}</style></head><body>
<header><p>OMANOVA / {'SIMULATED EXAMPLES' if d['source']=='sample' else 'SAVED OFFLINE SNAPSHOT'}</p><h1>Your night: {e(d['night'])}</h1><p>Guide zone: {e(d['zone'])}. Noon to noon: {e(d['windowStart'])} — {e(d['windowEnd'])} UTC.</p>
<p>Saved {e(d['savedAt'])}. Prediction snapshot {e(d['capturedAt'])}. No address, coordinates or location name included.</p><p class="warning">{'SIMULATED: not real predictions. ' if d['source']=='sample' else ''}Recheck timing, weather, local horizon and safety before observing. No automatic updates, alarms or live visibility guarantee. Source links are references only. Manual/terrain horizons and Trip Planner destinations have not been applied by this guide.</p><p>On-screen freshness uses this device's clock. Printed copies cannot update: use the timestamps and recheck deadlines on each card.</p><noscript><p class="warning">Dynamic age checks are unavailable. Treat freshness as unknown; inspect each saved timestamp and recheck deadline.</p></noscript></header>
{''.join(cards)}<script>{script}</script></body></html>'''


def run(state,action,payload,now=None):
    now=now or datetime.now(UTC)
    with lock(state):
        if action=='open':
            guide=payload.get('guide');deck=load_saved(state,guide);mode='saved'
        elif action=='save':guide,deck=save(state,payload,now);mode='saved'
        elif action in ('init','refresh'):guide='';deck=prepare(state,payload,now);mode='draft'
        else:raise ValueError('Unknown action')
        shown=view(deck,now if mode=='saved' else utc(deck['capturedAt']))
        write(state/'view.json',{'mode':mode,'guide':guide,'html':str(state/'guides'/guide/'guide.html') if guide else '', 'deck':shown,'saved':saved_list(state)})


def main():
    p=argparse.ArgumentParser();p.add_argument('--state',type=Path,required=True);p.add_argument('action',choices=('init','refresh','save','open'));a=p.parse_args();state=a.state.resolve()
    if not state.is_relative_to((ROOT/'.preview').resolve()):raise ValueError('Use this checkout preview directory')
    os.umask(0o077);payload={}
    if a.action!='init':
        raw=sys.stdin.buffer.readline(16385)
        if len(raw)>16384 or not raw.endswith(b'\n'):raise ValueError('Expected one bounded request')
        payload=json.loads(raw)
        if not isinstance(payload,dict):raise ValueError('Expected an observing guide request')
    run(state,a.action,payload);print('Offline guide preview updated')

if __name__=='__main__':
    try:main()
    except (ValueError,OSError,KeyError,TypeError,AttributeError,OverflowError,ZoneInfoNotFoundError):raise SystemExit('Could not update the offline guide. Check night, time zone and selection; saved files have been retained.')
