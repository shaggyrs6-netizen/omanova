"""Local destination catalogue and small, cached-kernel sky finder. No network calls."""
import argparse
from contextlib import closing
from datetime import UTC,datetime,timedelta
import hashlib,json,math,os,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from astronomy import iso,utc,DIRECTIONS
from worker import read,write,lock,DEFAULT_STATE,location,settings_at
from observatory.trips.trips import validate_config,system_zone,night_bounds,geometry,local_stamp
from observatory.trips.horizon import place_key
from observatory.trips.terrain import load_profile,combined_altitude
from observatory.moon.moon import intervals
from observing_context import trip_state,equipment_profile,match
DATA=Path(os.environ.get('XDG_DATA_HOME') or Path.home()/'.local/share')
LIVE_STATE=DATA/'omanova-field'
CAT=json.loads((Path(__file__).parent/'catalog.json').read_text())
SITES=json.loads((Path(__file__).parent/'sites.json').read_text())

def distance(lat1,lon1,lat2,lon2):
    a,b=math.radians(lat1),math.radians(lat2);c=math.sin((b-a)/2)**2+math.cos(a)*math.cos(b)*math.sin(math.radians(lon2-lon1)/2)**2
    return 6371.0088*2*math.asin(min(1,math.sqrt(max(0,c))))

def point(source,fixture=False,load_terrain=True):
    if fixture:return {'name':'Public Nashville sample','lat':36.1627,'lon':-86.7816,'elevation':0,'timezone':'America/Chicago','horizon':[],'observingHeight':1.7,'useTerrain':False},None
    if source in ('trip-home','trip-destination'):
        config=validate_config(read(trip_state()/'trip.json',{}));p=config['home' if source=='trip-home' else 'destination']
    elif source=='active':
        p=location(settings_at(DEFAULT_STATE))
        if not p:raise ValueError('Set an observing location first')
        p={**p,'timezone':system_zone(),'horizon':[],'useTerrain':False,'observingHeight':1.7}
        config=read(trip_state()/'trip.json',{})
        if config:
            config=validate_config(config)
            for key in ('home','destination'):
                if place_key(config[key])==place_key(p):p=config[key];break
    else:raise ValueError('Choose active, Trip Home or Trip destination')
    terrain=load_profile(p,trip_state()) if p.get('useTerrain') and load_terrain else None
    if p.get('useTerrain') and load_terrain and terrain is None:raise ValueError('Enabled terrain missing: estimate again in Trip Planner or switch it off')
    return p,terrain

def sites(source='active',fixture=False,now=None):
    now=now or datetime.now(UTC);p,_=point(source,fixture,load_terrain=False);rows=[]
    regional=json.loads((ROOT/'observatory/dark-sites/sites.json').read_text())
    for s in regional['sites']:
        rows.append({'name':s['name'],'area':s['area'],'lat':s['latitude'],'lon':s['longitude'],'darkness':s['darkness']+' · '+s['darknessDetail'],
                     'access':s['access']+' · '+s['accessDetail'],'source':s['visit'],'checked':regional['checked']})
    for s in SITES['sites']:rows.append({**s,'checked':SITES['checked']})
    for r in rows:
        r['distanceKm']=round(distance(p['lat'],p['lon'],r['lat'],r['lon']),1)
        r['evidenceOld']=(now.date()-datetime.fromisoformat(r['checked']).date()).days>90
    rows.sort(key=lambda r:r['distanceKm'])
    return {'source':source,'fixture':fixture,'generated':iso(now),'rows':rows,'limits':SITES['limits'],
            'origin':'Public Nashville sample' if fixture else 'Active location' if source=='active' else source.replace('-',' ').title(),
            'distanceBasis':'Great-circle straight-line distance, not a road route, drive time or access permission. Coordinates are approximate site reference points.'}

def finder(request,fixture=False,now=None):
    from skyfield.api import load,load_file,wgs84,Star
    from skyfield import almanac
    import numpy as np
    now=now or datetime.now(UTC);source=request.get('source','active');p,terrain=point(source,fixture)
    tz=p['timezone'];local=now.astimezone(__import__('zoneinfo').ZoneInfo(tz))
    day=__import__('datetime').date.fromisoformat(request.get('night') or (local.date()-timedelta(days=local.hour<12)).isoformat())
    if not 2000<=day.year<=2050:raise ValueError('Choose a night from 2000 to 2050')
    start,end=night_bounds(day,tz);ts=load.timescale(builtin=True);rows=[]
    selected=equipment_profile() if not fixture else __import__('observatory.equipment.equipment',fromlist=['profile']).profile({})
    with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
        observer=eph['earth']+wgs84.latlon(p['lat'],p['lon'],elevation_m=p['elevation']+p.get('observingHeight',1.7))
        def sun(t):return observer.at(t).observe(eph['sun']).apparent().altaz()[0].degrees
        def dark(t):return sun(t)<=-18
        def moonfree(t):return dark(t)&(observer.at(t).observe(eph['moon']).apparent().altaz()[0].degrees<0)
        dark.step_days=moonfree.step_days=1/48
        ds=list(intervals(ts,start,end,dark));ms=list(intervals(ts,start,end,moonfree))
        darkness={'darkHours':round(sum((b-a).total_seconds() for a,b in ds)/3600,1),'moonFreeHours':round(sum((b-a).total_seconds() for a,b in ms)/3600,1),
                  'basis':'Astronomical darkness (Sun below −18°) and Moon-below-horizon time; not a Bortle/SQM or light-pollution estimate. Cloud and glare remain unknown.'}
        for target in CAT['landmarks']+CAT['targets']:
            body=Star(ra_hours=target['ra'],dec_degrees=target['dec']);landmark=target in CAT['landmarks'];threshold=-6 if landmark else -18
            def position(t):return observer.at(t).observe(body).apparent().altaz()
            def clear(t):
                alt,az,_=position(t)
                return (sun(t)<=threshold)&(alt.degrees>=20)&(alt.degrees>combined_altitude(az.degrees,p['horizon'],terrain))
            clear.step_days=1/288
            windows=[]
            for a,b in intervals(ts,start,end,clear):
                if (b-a).total_seconds()<60:continue
                points=[a+(b-a)*i/60 for i in range(61)];alt,az,_=position(ts.from_datetimes(points));index=int(np.argmax(alt.degrees));when=points[index]
                bearing=float(az.degrees[index]);height=float(alt.degrees[index]);moonalt=float(observer.at(ts.from_datetime(when)).observe(eph['moon']).apparent().altaz()[0].degrees)
                r={'id':target['id']+'-'+iso(a),'kind':'landmark' if landmark else 'deep-sky','name':target['name'],'start':iso(a),'end':iso(b),
                   'look':{'time':iso(when),'az':round(bearing,1),'el':round(height,1),'direction':DIRECTIONS[int((bearing+11.25)//22.5)%16]},
                   'visibility':'unconfirmed','conditions':{'label':'Uncertain','reason':'No forecast is fetched by the finder'},'recommended':False,'reason':target['hint'],
                   'source':target.get('source',CAT['coordinateSource']),'valid_until':iso(now+timedelta(hours=2))}
                assessment=match(r,selected,now)
                fov=selected.get('fieldOfViewDeg');extent=target.get('extent')
                framing='Field of view not supplied; full-target framing unassessed.' if not fov or not extent else 'Target fits the supplied field approximately; camera framing/optical projection still vary.' if fov>=extent else 'Full target exceeds the supplied field; central detail may still be visible.'
                windows.append({'when':local_stamp(a,tz)+' — '+local_stamp(b,tz),'lookWhen':local_stamp(when,tz),'event':r,'equipment':assessment['notes'] if assessment else ['Equipment unknown'],'profileExcluded':bool(selected['filter'] and assessment and assessment['excluded']),
                    'moonAltitude':round(moonalt),'moonPercent':round(100*float(almanac.fraction_illuminated(eph,'moon',ts.from_datetime(when)))), 'framing':framing})
            rows.append({**target,'kind':'landmark' if landmark else 'deep-sky','windows':windows,'status':'Potential geometry only; brightness/conditions unconfirmed' if windows else 'No usable window: below threshold, daylight or saved horizon blocked'})
    return {'source':source,'fixture':fixture,'night':day.isoformat(),'zone':tz,'generated':iso(now),'rows':rows,'darkness':darkness,
            'horizon':'Saved manual sectors and enabled terrain applied; no new terrain downloads.','limits':CAT['coordinateBasis']+' Minimum 20° elevation; twilight for bright landmarks, astronomical darkness for deep-sky targets. No GO, weather guarantee, refraction or telescope alignment solution.'}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--state',required=True,type=Path);parser.add_argument('--fixture',action='store_true');parser.add_argument('action',choices=('sites','finder'));args=parser.parse_args()
    state=args.state.resolve()
    if state!=LIVE_STATE.resolve() and not state.is_relative_to((ROOT/'.preview').resolve()):raise ValueError('Use the dedicated field state')
    os.umask(0o077);raw=sys.stdin.buffer.readline(8193)
    if len(raw)>8192 or not raw.endswith(b'\n'):raise ValueError('Expected a bounded request')
    request=json.loads(raw)
    if not isinstance(request,dict):raise ValueError('Invalid field request')
    with lock(state):write(state/(args.action+'.json'),sites(request.get('source','active'),args.fixture) if args.action=='sites' else finder(request,args.fixture))
    print('Field view updated')
if __name__=='__main__':
    try:main()
    except (ValueError,OSError,KeyError,TypeError,OverflowError):raise SystemExit('Field view unavailable. Check location, night and saved terrain in Trip Planner. Existing data were retained.')
