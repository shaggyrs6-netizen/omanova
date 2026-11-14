"""Isolated trip/horizon preview. Private requests travel over stdin only."""
import argparse
from contextlib import closing
from datetime import datetime,date,time,timedelta,timezone
import hashlib
import json
from math import isfinite
import os
from pathlib import Path
import sys
from urllib.parse import urlencode
from zoneinfo import ZoneInfo,ZoneInfoNotFoundError

import numpy as np
from skyfield import almanac
from skyfield.api import load,load_file,wgs84,EarthSatellite

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from astronomy import DIRECTIONS,STATIONS,predict,iso,utc
from conditions import FIELDS,classify,weather_hours
from worker import DEFAULT_STATE,FORECAST_URL,get_json,location,read,settings_at,update_source,write
from observatory.moon.moon import intervals
from observatory.meteors.meteors import CATALOG as METEORS
from observatory.trips.horizon import altitude as horizon_altitude,validate as validate_horizon,place_key

from observatory.trips.terrain import observing_height,load_profile,estimate,combined_altitude

UTC=timezone.utc
PLANETS=('Mercury','Venus','Mars','Jupiter','Saturn')


def zone(name):
    if not isinstance(name,str) or len(name)>80:raise ValueError('Choose an IANA time zone, such as America/Chicago')
    try:return ZoneInfo(name)
    except (ZoneInfoNotFoundError,ValueError):raise ValueError('Time zone not recognised. Use a name such as America/Chicago or Europe/London') from None


def validate_place(raw):
    if not isinstance(raw,dict):raise ValueError('Choose Home and a destination')
    name=' '.join(str(raw.get('name','')).split())
    try:lat,lon,elevation=(float(raw.get(k,0) if k=='elevation' else raw[k]) for k in ('lat','lon','elevation'))
    except (KeyError,ValueError,TypeError):raise ValueError('Enter valid coordinates and elevation') from None
    if not name or len(name)>64 or not all(map(isfinite,(lat,lon,elevation))):raise ValueError('Enter a short place name and finite coordinates')
    if not -90<=lat<=90 or not -180<=lon<=180 or not -500<=elevation<=9000:raise ValueError('Coordinates or elevation are outside supported ranges')
    tz=raw.get('timezone');zone(tz)
    if type(raw.get('useTerrain',False)) is not bool:raise ValueError('Choose whether to use the terrain estimate')
    return {'name':name,'lat':lat,'lon':lon,'elevation':elevation,'timezone':tz,'horizon':validate_horizon(raw.get('horizon',[])),
            'observingHeight':observing_height(raw.get('observingHeight',1.7)),'useTerrain':raw.get('useTerrain',False)}


def validate_config(raw):
    if not isinstance(raw,dict):raise ValueError('Invalid trip settings')
    home,destination=(validate_place(raw.get(k)) for k in ('home','destination'))
    try:first,last=(date.fromisoformat(raw[k]) for k in ('start','end'))
    except (KeyError,TypeError,ValueError):raise ValueError('Use YYYY-MM-DD for both trip dates') from None
    if not 2000<=first.year<=2050 or not 2000<=last.year<=2050 or not 0<=(last-first).days<14:
        raise ValueError('Choose 1–14 observing nights, between 2000 and 2050')
    if type(raw.get('weather',False))!=bool:raise ValueError('Weather consent must be true or false')
    if place_key(home)==place_key(destination) and home['horizon']!=destination['horizon']:
        raise ValueError('The same observing point must use the same horizon in both columns')
    store=raw.get('horizonStore',{})
    if not isinstance(store,dict) or len(store)>50:raise ValueError('The preview stores at most 50 place horizons')
    store={str(k)[:100]:validate_horizon(v) for k,v in store.items()}
    for place in (home,destination):store[place_key(place)]=place['horizon']
    if len(store)>50:raise ValueError('The preview stores at most 50 place horizons')
    return {'home':home,'destination':destination,'start':first.isoformat(),'end':last.isoformat(),
            'weather':raw.get('weather',False),'horizonStore':store}


def night_bounds(day,tz):
    """Local noon to next local noon; never assume a 24-hour DST day."""
    z=zone(tz)
    return (datetime.combine(day,time(12),z).astimezone(UTC),
            datetime.combine(day+timedelta(days=1),time(12),z).astimezone(UTC))


def local_stamp(instant,tz):
    local=instant.astimezone(zone(tz));offset=local.strftime('%z')
    return local.strftime('%a %d %b · %H:%M %Z')+' (UTC'+offset[:3]+':'+offset[3:]+')'


def dual(instant,config):
    return {'utc':iso(instant),'home':local_stamp(instant,config['home']['timezone']),
            'destination':local_stamp(instant,config['destination']['timezone'])}


def weather_for(place,start,end,state,enabled,now,fetch=get_json):
    if not enabled:return {},None,'Weather off · astronomy-only comparison'
    if start>now+timedelta(days=7) or end<now-timedelta(days=1):
        return {},None,'Outside the current forecast horizon · no forecast downloaded'
    key=f"{place['lat']:.2f},{place['lon']:.2f}"
    path=state/('weather-'+hashlib.sha256(key.encode()).hexdigest()[:16]+'.json')
    cache=read(path,{})
    if not isinstance(cache,dict):cache={}
    lat,lon=key.split(',')
    query=urlencode({'latitude':lat,'longitude':lon,'hourly':','.join(FIELDS),'timezone':'GMT','forecast_days':7})
    update_source(cache,now,timedelta(hours=3),lambda:fetch(FORECAST_URL+'?'+query),weather_hours)
    write(path,cache)
    try:hours=weather_hours(cache.get('data',{}))
    except (ValueError,KeyError,TypeError):hours={}
    return hours,cache.get('fetched'),('Forecast unavailable' if not hours else 'Rounded-location Open-Meteo forecast; distant dates may be uncovered')


def geometry(eph,ts,place,day,config,hours,fetched,now):
    start,end=night_bounds(day,place['timezone'])
    site=wgs84.latlon(place['lat'],place['lon'],elevation_m=place['elevation']+place.get('observingHeight',1.7))
    observer=eph['earth']+site
    def sun_alt(t):return observer.at(t).observe(eph['sun']).apparent().altaz()[0].degrees
    def dark(t):return sun_alt(t)<=-18
    def moon_down(t):return observer.at(t).observe(eph['moon']).apparent().altaz()[0].degrees<-.3
    def moonless(t):return dark(t)&moon_down(t)
    dark.step_days=moonless.step_days=1/48
    darkness=list(intervals(ts,start,end,dark));moonfree=list(intervals(ts,start,end,moonless))
    midpoint=start+(end-start)/2
    illumination=100*float(almanac.fraction_illuminated(eph,'moon',ts.from_datetime(midpoint)))
    result={'date':day.isoformat(),'darkHours':round(sum((b-a).total_seconds() for a,b in darkness)/3600,1),
            'moonFreeHours':round(sum((b-a).total_seconds() for a,b in moonfree)/3600,1),
            'moonPercent':round(illumination),'darkness':[{'start':dual(a,config),'end':dual(b,config)} for a,b in darkness],
            'targets':[]}
    for name in ('Moon',*PLANETS):
        body=eph[name.lower()+(' barycenter' if name in ('Mars','Jupiter','Saturn') else '')]
        minimum=5 if name=='Moon' else 10
        def position(t):return observer.at(t).observe(body).apparent().altaz()
        def possible(t):return (sun_alt(t)<=-6)&(position(t)[0].degrees>=minimum)
        def clear(t):
            alt,az,_=position(t)
            return possible(t)&(alt.degrees>combined_altitude(az.degrees,place['horizon'],place.get('_terrain')))
        possible.step_days=clear.step_days=1/1440
        base=list(intervals(ts,start,end,possible));usable=list(intervals(ts,start,end,clear)) if place['horizon'] or place.get('_terrain') else base
        windows=[]
        for a,b in usable:
            if (b-a).total_seconds()<60:continue
            points=[a+(b-a)*i/100 for i in range(101)]
            alt,az,_=position(ts.from_datetimes(points));index=int(np.argmax(alt.degrees))
            when=points[index];bearing=float(az.degrees[index]);height=float(alt.degrees[index])
            windows.append({'start':dual(a,config),'end':dual(b,config),'look':dual(when,config),
                'bearing':round(bearing),'altitude':round(height),'direction':DIRECTIONS[int((bearing+11.25)//22.5)%16],
                'conditions':classify({'start':{'time':iso(a)},'end':{'time':iso(b)}},hours,fetched,now,config['weather'])})
        base_seconds=sum((b-a).total_seconds() for a,b in base)
        clear_seconds=sum((b-a).total_seconds() for a,b in usable)
        result['targets'].append({'name':name,'windows':windows,'blockedMinutes':round(max(0,base_seconds-clear_seconds)/60),
            'status':'Clear windows' if windows else 'Blocked by your horizon' if base_seconds>60 else 'No twilight viewing window'})
    return result


def station_windows(eph,ts,place,start,end,config,orbit):
    fresh=[]
    if not isinstance(orbit,dict) or not isinstance(orbit.get('data'),list) or len(orbit['data'])>256:
        return [],'Cached station elements are unavailable; recheck closer to the trip.'
    for row in orbit.get('data',[]):
        try:
            epoch=utc(row['EPOCH'])
            if row['NORAD_CAT_ID'] in STATIONS and start-timedelta(hours=72)<=epoch<=start+timedelta(hours=6):fresh.append(row)
        except (KeyError,ValueError,TypeError):continue
    if not fresh:return [],'Cached station elements do not cover these dates reliably. Recheck closer to the trip.'
    catalogue={row['NORAD_CAT_ID']:STATIONS[row['NORAD_CAT_ID']] for row in fresh}
    covered_end=min(end,min(utc(row['EPOCH'])+timedelta(hours=72) for row in fresh))
    if covered_end<=start:return [],'Newer orbital elements are needed for these dates.'
    prediction_place={**place,'elevation':place['elevation']+place.get('observingHeight',1.7),'id':'trip-'+hashlib.sha256(place_key(place).encode()).hexdigest()[:12]}
    try:passes=predict(fresh,ts,eph,prediction_place,start,days=(covered_end-start).total_seconds()/86400,catalog=catalogue)
    except (ValueError,TypeError,KeyError):return [],'Cached station data are invalid; the Moon/planet comparison is still available.'
    models={row['NORAD_CAT_ID']:EarthSatellite.from_omm(ts,row) for row in fresh}
    site=wgs84.latlon(place['lat'],place['lon'],elevation_m=place['elevation']+place.get('observingHeight',1.7))
    result=[]
    for item in passes:
        for window in item['windows']:
            first,last=max(start,utc(window['start']['time'])),min(end,utc(window['end']['time']))
            if last<=first:continue
            sat=models[item['source_id']]
            def position(t):return (sat-site).at(t).altaz()
            def clear(t):
                alt,az,_=position(t)
                return alt.degrees>combined_altitude(az.degrees,place['horizon'],place.get('_terrain'))
            clear.step_days=1/86400
            segments=list(intervals(ts,first,last,clear)) if place['horizon'] or place.get('_terrain') else [(first,last)]
            for a,b in segments:
                if (b-a).total_seconds()<2:continue
                points=[a+(b-a)*i/60 for i in range(61)]
                alt,az,_=position(ts.from_datetimes(points));index=int(np.argmax(alt.degrees))
                bearing=float(az.degrees[index])
                result.append({'name':item['name'],'start':dual(a,config),'end':dual(b,config),'look':dual(points[index],config),
                    'bearing':round(bearing),'altitude':round(float(alt.degrees[index])),
                    'direction':DIRECTIONS[int((bearing+11.25)//22.5)%16]})
    return result,'Cached geometry only for dates covered by fresh elements; other dates need newer data. Passes can change. No orbital download was made.'


def compare(config,state,now=None,orbit=None,schedule=None):
    config=validate_config(config);now=now or datetime.now(UTC)
    days=[date.fromisoformat(config['start'])+timedelta(days=i) for i in range((date.fromisoformat(config['end'])-date.fromisoformat(config['start'])).days+1)]
    ts=load.timescale(builtin=True)
    result={'generated':iso(now),'home':{},'destination':{},'dates':[d.isoformat() for d in days],
        'basis':'Each column uses its own local evening on the selected date (local noon to the following noon), not the same UTC interval.',
        'limits':'Manual obstructions and any enabled terrain estimate clip viewing windows. Terrain is sampled within 50 km only; narrow/distant ridges can be missed. These estimates do not model light pollution, cloud transparency or sighting probability.'}
    orbit=orbit if orbit is not None else read(DEFAULT_STATE/'orbit.json',{})
    with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
        for key in ('home','destination'):
            place=config[key]
            if place['useTerrain']:
                place['_terrain']=load_profile(place,state)
                if not place['_terrain']:raise ValueError('Terrain estimate missing for this location/height. Estimate it again or switch terrain off; manual obstructions remain.')
            start=night_bounds(days[0],place['timezone'])[0];end=night_bounds(days[-1],place['timezone'])[1]
            hours,fetched,weather_note=weather_for(place,start,end,state,config['weather'],now)
            nights=[geometry(eph,ts,place,d,config,hours,fetched,now) for d in days]
            stations,station_note=station_windows(eph,ts,place,start,end,config,orbit)
            active=[{'name':r['name'],'start':r['activeStart'],'end':r['activeEnd'],'peak':r['peak']}
                    for r in METEORS['showers'] if r['activeStart']<=days[-1].isoformat() and r['activeEnd']>=days[0].isoformat()]
            result[key]={'name':place['name'],'timezone':place['timezone'],'nights':nights,'stations':stations,
                'stationNote':station_note,'weatherNote':weather_note,'meteors':active,
                'clearWindowCount':sum(len(t['windows']) for n in nights for t in n['targets']),
                'blockedMinutes':sum(t['blockedMinutes'] for n in nights for t in n['targets'])}
    from observing_context import trip_signature
    result['configurationHash']=trip_signature(config,state)
    # Global launch schedules are useful while travelling, but are not local visibility predictions.
    schedule=schedule if schedule is not None else read(DEFAULT_STATE/'planning/launches/launches.json',{})
    start=night_bounds(days[0],config['destination']['timezone'])[0];end=night_bounds(days[-1],config['destination']['timezone'])[1]
    if not isinstance(schedule,dict):schedule={}
    result['launches']=[]
    for row in schedule.get('launches',[]):
        try:
            stamp=utc(row['net'])
            if start<=stamp<=end:result['launches'].append({'name':row['name'],'time':dual(stamp,config) if row['precision'] in ('SEC','MIN','HR') else None,
                'providerDate':stamp.date().isoformat(),'status':row['status'],'source':row['source'],'precision':row['precision']})
        except (KeyError,TypeError,ValueError):continue
    result['launchNote']='Cached schedule only; local launch visibility is unconfirmed. Recheck dates and status before travel.'
    result['launchFetched']=schedule.get('fetched')
    try:result['launchStale']=not timedelta(0)<=now-utc(schedule['fetched'])<timedelta(hours=2)
    except (KeyError,ValueError,TypeError):result['launchStale']=True
    return result


def system_zone():
    path=str(Path('/etc/localtime').resolve())
    if '/zoneinfo/' in path:
        name=path.split('/zoneinfo/',1)[1]
        try:zone(name);return name
        except ValueError:pass
    return 'UTC'


def initialise(state,fixture):
    existing=read(state/'trip.json',None)
    if existing:
        config=validate_config(existing);config['weather']=False
        write(state/'trip.json',config);return
    home={'name':'Home · Nashville sample','lat':36.1627,'lon':-86.7816,'elevation':0,'timezone':'America/Chicago','horizon':[]}
    if not fixture:
        settings=settings_at(DEFAULT_STATE)
        saved=next((p for p in settings['profiles'] if p['name'].casefold()=='home'),None) or location(settings)
        if saved:home={k:saved[k] for k in ('name','lat','lon','elevation')} | {'timezone':system_zone(),'horizon':[]}
    destination={'name':'London example','lat':51.5074,'lon':-.1278,'elevation':10,'timezone':'Europe/London','horizon':[]}
    day=date(2026,11,20) if fixture else datetime.now(zone(destination['timezone'])).date()+timedelta(days=7)
    config={'home':home,'destination':destination,'start':day.isoformat(),'end':(day+timedelta(days=2)).isoformat(),'weather':False,'horizonStore':{}}
    write(state/'trip.json',validate_config(config))


def main():
    p=argparse.ArgumentParser();p.add_argument('command',choices=('init','compare','lookup','terrain','terrain-status'));p.add_argument('--state',type=Path,required=True);p.add_argument('--fixture',action='store_true');p.add_argument('--copy-trip',type=Path);args=p.parse_args()
    state=args.state.resolve()
    if state==DEFAULT_STATE.resolve() or DEFAULT_STATE.resolve() in state.parents:raise ValueError('Use a separate preview directory')
    os.umask(0o077);state.mkdir(mode=0o700,parents=True,exist_ok=True);state.chmod(0o700)
    if args.command=='init':
        if args.copy_trip and not (state/'trip.json').exists() and args.copy_trip.is_file():
            config=validate_config(read(args.copy_trip,{}));config['weather']=False
            # A preview copy never silently enables terrain from another state directory.
            for key in ('home','destination'):config[key]['useTerrain']=False
            write(state/'trip.json',config)
        initialise(state,args.fixture);return
    raw=sys.stdin.buffer.readline(65537)
    if len(raw)>65536 or not raw.endswith(b'\n'):raise ValueError('Expected one bounded request on stdin')
    try:payload=json.loads(raw)
    except (ValueError,UnicodeError):raise ValueError('Could not read the preview request') from None
    if args.command in ('terrain','terrain-status'):
        place=validate_place(payload['place'])
        if args.command=='terrain-status':profile=load_profile(place,state)
        else:profile=estimate(place,state,allowed=payload.get('download',False))
        print(json.dumps(profile));return
    if args.command=='lookup':
        from place_lookup import search
        rows=search(payload)
        print(json.dumps(rows));return
    config=validate_config(payload)
    output=compare(config,state,orbit={} if args.fixture else None,schedule={} if args.fixture else None)
    write(state/'trip.json',{**config,'weather':False})
    write(state/'comparison.json',output)
    print('Comparison ready')


if __name__=='__main__':
    try:main()
    except (OSError,ValueError,TypeError,KeyError) as exc:
        message=str(exc) if isinstance(exc,ValueError) else 'Comparison unavailable. Check the local runtime and try again.'
        print(message,file=sys.stderr);sys.exit(1)
