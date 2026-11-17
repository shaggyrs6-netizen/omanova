"""Read-only, network-free Mission Control view of an installed OMANOVA runtime.

Only fixed state/runtime paths travel in argv. Private coordinates remain in
local files and the child stdout pipe, never process arguments or diagnostics.
"""
import argparse
import json
import os
from pathlib import Path
import sys
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo


def fresh(value, now, seconds):
    try:
        age=(now-datetime.fromisoformat(value.replace('Z','+00:00'))).total_seconds()
        return 0 <= age <= seconds
    except (ValueError,TypeError,AttributeError):return False


def cards(state, settings, place, now, read, utc, forecast_key, weather_hours):
    snap=read(state/'snapshot.json',{})
    valid=(fresh(snap.get('generated'),now,180) and not snap.get('demo') and
           snap.get('place',{}).get('lat')==place['lat'] and snap.get('place',{}).get('lon')==place['lon'])
    passes={}
    for number in (25544,48274):
        rows=[]
        if valid:
            for event in snap.get('events',[]):
                try:
                    if event.get('source_id')!=number or not -6 <= (now-utc(event['element_epoch'])).total_seconds()/3600 <=48:continue
                    if utc(event['end'])<=now:continue
                    rows.append(event)
                except (KeyError,ValueError,TypeError):continue
        rows.sort(key=lambda r:r['start'])
        row=rows[0] if rows else None
        passes[str(number)]={'value':'Predictions unavailable','detail':'Snapshot missing, stale or no upcoming pass'}
        if row:
            rise=row['rise'];clock=utc(row['start']).astimezone(ZoneInfo(place['timezone'])).strftime('%a %H:%M')
            passes[str(number)]={'value':row['name']+' · '+clock,'detail':f"Look {rise['direction']} · {row['culmination']['el']:.0f}° peak · visibility unconfirmed"}
    weather=read(state/'weather.json',{});cloud={'value':'Weather unavailable','detail':'Forecast missing, stale or downloads off'}
    if settings.get('weather') and weather.get('key')==forecast_key(place) and fresh(weather.get('fetched'),now,21600):
        try:
            hours=weather_hours(weather['data']);r=hours.get(now.replace(minute=0,second=0,microsecond=0))
            if r and r['cloud_cover'] is not None:cloud={'value':f"Cloud {r['cloud_cover']:.0f}%",'detail':('Cached forecast · refresh failed' if weather.get('error') else 'Area forecast')+' · visibility uncertain'}
        except (KeyError,ValueError,TypeError):pass
    launch={'value':'Launch data unavailable','detail':'Feed missing, stale or downloads off'}
    cache=read(state/'planning/launches/launches.json',{})
    if settings.get('launches') and not cache.get('fixture') and fresh(cache.get('fetched'),now,21600):
        upcoming=[]
        for r in cache.get('launches',[]):
            try:
                if utc(r['net'])>now:upcoming.append(r)
            except (ValueError,TypeError,KeyError):pass
        if upcoming:
            r=min(upcoming,key=lambda r:r['net']);clock=utc(r['net']).astimezone(ZoneInfo(place['timezone'])).strftime('%a %H:%M')
            launch={'value':r['name'],'detail':clock+' · '+r.get('status','Schedule unconfirmed')+' · visibility unconfirmed'}
    return {'passes':passes,'weather':cloud,'launch':launch,'snapshotFresh':valid}


def build(runtime,state,now=None):
    # Imports inherit an isolated data root in tests, the real configured root in live use.
    os.environ['XDG_DATA_HOME']=str(state.parent)
    sys.path.insert(0,str(runtime))
    from astronomy import utc,iso,station_rows,STATIONS
    from worker import read,settings_at,forecast_key
    from conditions import weather_hours
    from observatory.field.field import point
    from observatory.final_sky.geometry import sky_chart
    from observatory.final_sky.satellite_layer import cached_rows,calculate
    from skyfield.api import load,load_file,EarthSatellite,wgs84
    from skyfield import almanac
    from contextlib import closing
    now=now or datetime.now(UTC);settings=settings_at(state)
    p,terrain=point('active',False)
    ts=load.timescale(builtin=True)
    with closing(load_file(str(runtime/'assets/de440s.bsp'))) as eph:
        chart=sky_chart(eph,ts,p,terrain,now)
        rows,_=cached_rows(state,False,runtime)
        layer=calculate(rows,STATIONS,ts,eph,p,terrain,now)
        by={}
        for raw in rows:
            try:
                for n,row in station_rows([raw],ts,require_all=False).items():
                    if n not in by or utc(row['EPOCH'])>utc(by[n]['EPOCH']):by[n]=row
            except (ValueError,TypeError,KeyError,OverflowError):pass
        for r in layer['objects']:
            sat=EarthSatellite.from_omm(ts,by[r['id']]);pos=sat.at(ts.from_datetime(now));sub=wgs84.subpoint_of(pos)
            times=ts.from_datetimes([now+timedelta(seconds=s) for s in range(-2700,2701,60)])
            positions=sat.at(times)
            if any(positions.message):raise ValueError('Track unavailable')
            track=wgs84.subpoint_of(positions)
            r.update(lat=float(sub.latitude.degrees),lon=float(sub.longitude.degrees),altitudeKm=float(sub.elevation.km),
                     groundTrack=[[float(a),float(b)] for a,b in zip(track.longitude.degrees,track.latitude.degrees)])
        t=ts.from_datetime(now);moon={'fraction':float(almanac.fraction_illuminated(eph,'moon',t)),
                                     'angle':float(almanac.moon_phase(eph,t).degrees)}
    selected_cards=cards(state,settings,p,now,read,utc,forecast_key,weather_hours)
    return {'mode':'live','generated':iso(now),'localClock':now.astimezone(ZoneInfo(p['timezone'])).strftime('%H:%M:%S'),
            'utcClock':now.strftime('%H:%M:%S'),'zone':p['timezone'],'chart':chart,'satellites':layer,
            'observer':{'lat':p['lat'],'lon':p['lon']},'moon':moon,'cards':selected_cards,
            'miles':settings.get('distance_unit')=='mi',
            'basis':'Read-only local data · calculated SGP4, not telemetry · sky looks up: east left · globe ground tracks ±45 min · visibility uncertain'}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--runtime',type=Path,required=True);parser.add_argument('--state',type=Path,required=True);args=parser.parse_args()
    try:
        result=build(args.runtime,args.state)
        print(json.dumps(result,allow_nan=False,separators=(',',':')))
    except Exception:
        # No private values or exception repr in logs/argv.
        print(json.dumps({'mode':'live','generated':datetime.now(UTC).isoformat(),'error':'Live calculation unavailable. Check the observing location, cached elements, terrain and runtime in OMANOVA.'}))
        return 1
    return 0
if __name__=='__main__':raise SystemExit(main())
