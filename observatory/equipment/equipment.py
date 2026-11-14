"""Read-only equipment/sky suitability trial. Does not change planner recommendations."""
import argparse
from copy import deepcopy
from datetime import UTC,datetime,timedelta
import json
from math import isfinite
import os
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from worker import DEFAULT_STATE,read,write,lock
from astronomy import iso,utc
from observatory.events.launches import stream_url

GEAR=('eye','binoculars','telescope','camera')
SKIES=('unknown','bright','moderate','dark')
DEFAULT={'gear':['eye'],'sky':'unknown','filter':True,'uncertain':True,'showExcluded':False}


def profile(raw):
    if not isinstance(raw,dict) or set(raw)-set(DEFAULT):raise ValueError('Invalid equipment profile')
    out={**deepcopy(DEFAULT),**raw};gear=out['gear']
    if not isinstance(gear,list) or len(gear)>4 or any(g not in GEAR for g in gear):raise ValueError('Choose recognised equipment')
    out['gear']=list(dict.fromkeys(gear))
    if out['sky'] not in SKIES:raise ValueError('Choose a sky description')
    for k in ('filter','uncertain','showExcluded'):
        if type(out[k]) is not bool:raise ValueError('Filter controls require true or false')
    return out


def rule(row,sample=False):
    """Conservative guidance, not telescope limiting-magnitude or exposure predictions."""
    kind=row['kind'];name=row['name'].casefold();reason=row.get('reason','')
    if sample and row.get('sampleRule')=='meteor-photo':
        return ['camera'],'dark','Wide-field camera exercise: tripod and exposure technique needed; no exposure prediction.'
    if kind=='moon':return list(GEAR),'any','Moon viewing fits all four choices. Telescope detail and camera results depend on the instrument.'
    if kind=='planet' and row['name'] in ('Mercury','Venus','Mars','Jupiter','Saturn'):
        return list(GEAR),'any','Bright-planet overview: an eye/camera may record a point; resolved detail requires appropriate optics.'
    if kind=='station':return ['eye','binoculars','camera'],'any','Track the pass with a wide view. Telescope tracking is not assessed; a camera does not guarantee a detailed station image.'
    if kind=='meteor':return ['eye','camera'],'dark','Meteors favour a wide field. Binocular/telescope-only selections are less suitable for watching a shower.'
    if kind=='comet':
        tier=re.match(r'^Equipment: (eye|binoculars|telescope|large)\.',reason)
        if tier:
            label=tier.group(1)
            options={'eye':['eye','binoculars','telescope'],'binoculars':['binoculars','telescope'],'telescope':['telescope'],'large':[]}[label]
            return options,'dark',('Existing dated comet guidance: '+label+'. Brightness is diffuse/variable; camera, aperture and tracking requirements are not inferred.')
        return None,'unknown','Comet equipment metadata unavailable; no limiting magnitude or camera capability is assumed.'
    if kind=='conjunction':return ['eye','camera'],'any','Wide-field pairing overview. Optical field of view and resolved detail are not known; binocular/telescope framing is unassessed.'
    if kind=='eclipse' and 'lunar' in name:return list(GEAR),'any','Lunar eclipse overview; camera scale and telescope detail depend on the instrument.'
    if kind in ('aurora','plume','train'):return ['eye','camera'],'dark','Wide-field experimental guidance. Equipment selection cannot confirm brightness or local visibility.'
    if kind=='launch':return None,'unknown','A launch schedule or webcast is not an established local observing target.'
    return None,'unknown','Equipment/brightness data are insufficient for a confident match.'


def clean_row(raw):
    if not isinstance(raw,dict):return None
    start,end=raw.get('start'),raw.get('end')
    try:
        if not start or not end or utc(end)<=utc(start):return None
    except (ValueError,TypeError,OverflowError):return None
    def text(k,limit=800):return str(raw.get(k,'') or '')[:limit]
    c=raw.get('conditions') if isinstance(raw.get('conditions'),dict) else {}
    look=raw.get('look') if isinstance(raw.get('look'),dict) else {}
    point={}
    for k in ('az','el'):
        v=look.get(k);point[k]=v if type(v) in (float,int) and isfinite(v) and (0<=v<360 if k=='az' else -90<=v<=90) else None
    point['direction']=str(look.get('direction',''))[:20]
    point['time']=str(look.get('time','') or '')[:80]
    score=raw.get('score',0);score=score if type(score) in (int,float) and isfinite(score) else 0
    return {'id':text('id',100),'kind':text('kind',30),'name':text('name',180),'start':start,'end':end,'look':point,
            'visibility':text('visibility',30),'reason':text('reason'),'safety':text('safety'),
            'valid_until':text('valid_until',80),'source':stream_url(raw.get('source')),
            'conditions':{'label':str(c.get('label','Uncertain'))[:40],'reason':str(c.get('reason',''))[:500],'fetched':c.get('fetched')},
            'recommended':raw.get('recommended') is True,'score':score}


def assess(raw,p,now,generated,sample=False,source_error=False):
    row=clean_row(raw)
    if row is None:return None
    if sample:row['sampleRule']=raw.get('sampleRule')
    options,sky,explanation=rule(row,sample)
    notes=[explanation];restricted=(row['kind']=='eclipse' and ('solar' in row['name'].casefold() or bool(row['safety'])))
    unknown_gear=options is None or options==[]
    gear_match=bool(set(p['gear'])&set(options or []))
    if not p['gear']:notes.append('No equipment selected.')
    elif unknown_gear:notes.append('Aperture, brightness or required capability is unknown; check the source.')
    elif not gear_match:notes.append('Your selected equipment does not match this overview rule.')
    sky_uncertain=sky!='any' and (p['sky']=='unknown' or sky=='unknown')
    sky_mismatch=sky=='dark' and p['sky'] in ('bright','moderate')
    if sky_uncertain:notes.append('Sky suitability unknown: a self-reported sky choice is not a measurement.')
    elif sky_mismatch:notes.append('Less suited to your sky description. A darker site is preferred; this does not mean observation is impossible.')
    else:notes.append('Sky description does not exclude this target; Moon, cloud and glare still matter.')
    stale=False
    try:
        stale=not timedelta(0)<=now-utc(generated)<=timedelta(minutes=3)
        if row['valid_until']:stale |= now>utc(row['valid_until'])
        stale |= utc(row['end'])<=now
        if row['look']['time']:stale |= utc(row['look']['time'])<now-timedelta(minutes=5)
    except (ValueError,TypeError,OverflowError):stale=True
    visibility=row['visibility']
    if stale:visibility='stale';notes.append('Source timing/data expired or is invalid.')
    weather=row['conditions']['label'];weather_unknown=weather not in ('Favourable','Mixed','Poor') or not row['conditions']['fetched']
    if not row['conditions']['fetched']:
        weather='Uncertain';notes.append('Forecast freshness unavailable.')
    try:
        if row['conditions']['fetched'] and not timedelta(0)<=now-utc(row['conditions']['fetched'])<timedelta(hours=6):weather_unknown=True;weather='Uncertain';notes.append('Forecast expired or future-dated.')
    except (ValueError,TypeError,OverflowError):weather_unknown=True;weather='Uncertain'
    row['conditions']['label']=weather
    if weather=='Poor':notes.append('Poor forecast remains a blocker; equipment does not improve the weather.')
    geometry_unknown=row['look']['az'] is None or row['look']['el'] is None or row['look']['el']<=0
    if geometry_unknown:notes.append('Above-horizon look direction unavailable; inspect the source before planning a sighting.')
    uncertain=geometry_unknown or unknown_gear or sky_uncertain or visibility!='possible' or weather_unknown or row['kind'] in ('aurora','plume','train') or source_error
    if restricted:notes.append('Solar safety review required: a general gear choice does not establish safe filters for eyes or optics.')
    blocked=not p['gear'] or (not unknown_gear and not gear_match) or sky_mismatch
    badge='Safety review required' if restricted else 'Filtered by profile' if blocked else 'Uncertain match' if uncertain else 'Equipment/sky match'
    filtered=blocked or restricted or (uncertain and not p['uncertain'])
    # Filtering can remove eligibility; it can never create it.
    eligible=row['recommended'] and not filtered and not uncertain and weather!='Poor' and visibility=='possible'
    if not row['recommended']:notes.append('The underlying planner did not recommend this event; profile matching cannot promote it.')
    return {**row,'visibility':visibility,'equipment':options or [],'skyRule':sky,'profileBadge':badge,'notes':notes,
            'excluded':filtered,'eligible':eligible,'uncertain':uncertain,'restricted':restricted}


def fixtures(now):
    entries=[('station','ISS',['possible','Favourable'],''),('moon','Moon',['possible','Favourable'],''),
             ('planet','Jupiter',['possible','Mixed'],''),('meteor','Meteor shower · wide view',['possible','Favourable'],''),
             ('meteor','Meteor photography exercise',['possible','Favourable'],'meteor-photo'),
             ('comet','Faint comet · telescope exercise',['possible','Favourable'],'telescope'),
             ('comet','Very faint comet · aperture unknown',['possible','Favourable'],'large'),
             ('satellite','Satellite · brightness unknown',['unconfirmed','Uncertain'],''),
             ('eclipse','Partial solar eclipse · safety example',['possible','Favourable'],''),
             ('eclipse','Lunar eclipse',['possible','Favourable'],''),
             ('aurora','Aurora · uncertain brightness',['unconfirmed','Uncertain'],''),
             ('planet','Venus',['possible','Poor'],''),('station','Expired station pass',['stale','Favourable'],''),
             ('launch','Launch webcast · no local geometry',['unconfirmed','Uncertain'],'')]
    rows=[]
    for i,(kind,name,flags,tag) in enumerate(entries):
        row={'id':'sample-'+str(i),'kind':kind,'name':name,'start':iso(now+timedelta(minutes=20+i*3)),
             'end':iso(now+timedelta(hours=2+i/10)),'look':{'az':140,'el':40,'direction':'SE'},'visibility':flags[0],
             'conditions':{'label':flags[1],'reason':'Simulated forecast','fetched':iso(now)},'recommended':flags[0]=='possible' and flags[1]!='Poor',
             'score':100-i,'source':'https://science.nasa.gov/skywatching/','reason':'Public sample geometry, not a current prediction.','valid_until':iso(now+timedelta(hours=3))}
        if kind=='comet':row['reason']='Equipment: '+tag+'. Magnitude estimate is a fictional fixture, not a live comet report.'
        if tag=='meteor-photo':row['sampleRule']=tag
        if kind=='eclipse' and 'solar' in name:row['safety']='Use appropriate safe solar viewers or front-mounted optical solar filters. Read NASA safety guidance.';row['source']='https://science.nasa.gov/eclipses/safety/'
        rows.append(row)
    return rows


def build(p,source,now,state,live_path=None):
    error='';generated=iso(now)
    if source=='sample':
        stored=read(state/'samples.json',None)
        if stored is None:
            stored={'clock':iso(now),'rows':fixtures(now)};write(state/'samples.json',stored)
        now=utc(stored['clock']);rows=stored['rows'];generated=stored['clock']
    else:
        path=live_path or DEFAULT_STATE/'planner.json'
        if path.exists() and path.stat().st_size>2097152:raise ValueError('Planning data exceeds preview limit')
        data=read(path,{})
        if not isinstance(data,dict):data={}
        rows=data.get('events',[]);generated=data.get('generated')
        if not isinstance(rows,list) or len(rows)>3000:raise ValueError('Unexpected planning data')
        if not rows:error='Live planner data unavailable or empty. No data were downloaded.'
        if data.get('issues'):error='Planner reports source issues; inspect the live Observatory for details. Matches remain uncertain.'
    assessed=[a for r in rows if (a:=assess(r,p,now,generated,sample=source=='sample',source_error=bool(error)))]
    visible=[r for r in assessed if not p['filter'] or p['showExcluded'] or not r['excluded']]
    visible.sort(key=lambda r:(r['excluded'],not r['eligible'],not r['recommended'],-r['score'],r['start']))
    return {'source':source,'profile':p,'generated':generated,'clock':iso(now),'error':error,'rows':visible[:200],
            'counts':{'total':len(assessed),'shown':min(200,len(visible)),'eligible':sum(r['eligible'] for r in assessed),
                      'uncertain':sum(r['uncertain'] for r in assessed),'excluded':sum(r['excluded'] for r in assessed)},
            'limits':'Equipment and sky rules are planning guidance. No telescope aperture, camera exposure, limiting magnitude, Bortle rating or actual sighting probability is predicted. Profile changes never enable downloads, alerts or GO recommendations.'}


def command(state,action,payload,now=None):
    now=now or datetime.now(UTC)
    with lock(state):
        stored=read(state/'profile.json',None)
        if stored is None and (state/'profile.json').exists():raise ValueError('Keep unreadable profile for inspection')
        p=profile(stored or {});source=read(state/'source.json',{'source':'sample'}).get('source','sample')
        if source not in ('sample','live'):raise ValueError('Invalid saved source selection')
        if action=='save':p=profile(payload);write(state/'profile.json',p)
        elif action=='source':
            source=payload.get('source')
            if source not in ('sample','live'):raise ValueError('Choose sample or read-only live suggestions')
            write(state/'source.json',{'source':source})
        elif action not in ('init','tick'):raise ValueError('Unknown profile action')
        write(state/'view.json',build(p,source,now,state))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--state',type=Path,required=True);parser.add_argument('action',choices=('init','save','source','tick'));args=parser.parse_args()
    state=args.state.resolve()
    if not state.is_relative_to((ROOT/'.preview').resolve()):raise ValueError('Use this checkout\'s preview directory')
    os.umask(0o077);payload={}
    if args.action in ('save','source'):
        raw=sys.stdin.buffer.readline(8193)
        if len(raw)>8192 or not raw.endswith(b'\n'):raise ValueError('Expected one bounded JSON request')
        payload=json.loads(raw)
    command(state,args.action,payload)
    print('Equipment preview updated')

if __name__=='__main__':
    try:main()
    except (OSError,ValueError,KeyError,TypeError,AttributeError,OverflowError):raise SystemExit('Could not update the equipment preview. Check the selection or local planning data.')
