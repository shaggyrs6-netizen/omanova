"""Local sky-plane positions from already downloaded elements; never fetches."""
from datetime import timedelta
import numpy as np
from skyfield.api import EarthSatellite,wgs84
from astronomy import STATIONS,iso,utc,station_rows
from observing_preferences import preferences
from worker import read,settings_at
from observatory.trips.terrain import combined_altitude


def cached_rows(state,fixture,root):
    settings=settings_at(state)
    catalog={**{r['number']:r['name'] for r in preferences(settings)['watchlist']},**STATIONS}
    paths=([root/'tests/fixtures/stations.json',root/'observatory/satellites/fixture-elements.json'] if fixture else
           [state/'orbit.json',state/'planning/satellites/orbit.json',*[state/f'planning/satellites/object-{n}.json' for n in catalog if n not in STATIONS]])
    rows=[]
    for path in paths:
        raw=read(path,[] if fixture else {})
        data=raw if fixture else raw.get('data',[]) if isinstance(raw,dict) else []
        if isinstance(data,list):rows.extend(data)
    return rows,catalog


def calculate(rows,catalog,ts,eph,p,terrain,now):
    # Validate separately so one broken/missing watchlist entry cannot hide ISS.
    selected={};issues=[]
    for raw in rows:
        if not isinstance(raw,dict) or raw.get('NORAD_CAT_ID') not in catalog:continue
        try:
            checked=station_rows([raw],ts,catalog=catalog,require_all=False)
            for n,r in checked.items():
                if n not in selected or utc(r['EPOCH'])>utc(selected[n]['EPOCH']):selected[n]=r
        except (ValueError,TypeError,KeyError,OverflowError):issues.append('Invalid cached elements withheld')
    site=wgs84.latlon(p['lat'],p['lon'],elevation_m=p['elevation']+p.get('observingHeight',1.7))
    time=ts.from_datetime(now);observer=(eph['earth']+site).at(time)
    sun=float(observer.observe(eph['sun']).apparent().altaz()[0].degrees)
    objects=[];withheld=[]
    for n,name in catalog.items():
        row=selected.get(n)
        if not row:
            withheld.append({'id':n,'name':name,'reason':'No cached elements; use existing orbital/watchlist download controls.'});continue
        age=(now-utc(row['EPOCH'])).total_seconds()/3600
        if not -6<=age<=48:
            withheld.append({'id':n,'name':name,'reason':'Stale or future elements','ageHours':round(age,2)});continue
        sat=EarthSatellite.from_omm(ts,row);position=sat.at(time)
        if position.message:
            withheld.append({'id':n,'name':name,'reason':'Propagation error'});continue
        alt,az,distance=(sat-site).at(time).altaz()
        el,a,km=float(alt.degrees),float(az.degrees),float(distance.km)
        if not all(np.isfinite([el,a,km])):continue
        clear=bool(el>combined_altitude(a,p.get('horizon',[]),terrain))
        sunlit=bool(position.is_sunlit(eph));possible=clear and el>=10 and sunlit and sun<=-6
        dates=[now+timedelta(seconds=s) for s in range(-30,91,5)]
        t=ts.from_datetimes(dates);path_alt,path_az,_=(sat-site).at(t).altaz()
        path=[{'az':float(b),'el':float(h)} for b,h in zip(path_az.degrees,path_alt.degrees) if h>=0]
        objects.append({'id':n,'name':name,'az':a,'el':el,'rangeKm':km,'clear':clear,'sunlit':sunlit,'skyDark':sun<=-6,
                        'potential':possible,'epoch':iso(utc(row['EPOCH'])),'ageHours':round(age,2),'path':path,
                        'status':'Potential geometry · weather/brightness unconfirmed' if possible else 'Not currently a potential viewing target'})
    return {'objects':objects,'withheld':withheld,'issues':sorted(set(issues)),
            'basis':'Calculated positions, not telemetry. Above-horizon markers only. Potential geometry means ≥10° up, clear of saved horizon, station sunlit and Sun ≤−6°. Brightness, clouds and actual visibility unconfirmed. Elements beyond 48 h old / 6 h future withheld. Short trail spans −30 to +90 s; no new downloads.'}
