"""Network-free sky chart, pole orientation, current stations and transit candidates.

Transit times are model candidates, never an observing guarantee. No ground
corridor is inferred from the kilometre-level uncertainty of public GP elements.
"""
from contextlib import closing
from datetime import UTC, datetime, timedelta
import argparse
import json
import math
from pathlib import Path
import sys
from zoneinfo import ZoneInfo
import numpy as np
from skyfield.api import EarthSatellite, Star, load, load_file, wgs84
from skyfield.constants import AU_KM
from skyfield.framelib import true_equator_and_equinox_of_date
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from astronomy import iso, utc, station_rows, STATIONS, pass_ranges
from worker import read, DEMO_NOW
from observatory.field.field import point
from observatory.trips.terrain import combined_altitude

CAT_PATH = Path(__file__).with_name('stars.json')
RADII = {'sun':695700.0, 'moon':1737.4}  # IAU nominal solar / mean lunar radius km


def stamp(dt):
    return dt.astimezone(UTC).isoformat(timespec='milliseconds').replace('+00:00','Z')


def separation(a, b):
    """Stable great-circle angle in degrees, including tiny transit angles."""
    a, b = np.asarray(a), np.asarray(b)
    return np.degrees(np.arctan2(np.linalg.norm(np.cross(a.T,b.T),axis=-1),np.sum(a*b,axis=0)))


def minimise(fn, lo, hi, tolerance=0.002):
    """Bounded golden-section minimum, within a bracket around one conjunction."""
    g = (math.sqrt(5)-1)/2
    c,d = hi-g*(hi-lo),lo+g*(hi-lo)
    fc,fd = fn(c),fn(d)
    while hi-lo > tolerance:
        if fc < fd:
            hi,d,fd = d,c,fc
            c = hi-g*(hi-lo);fc=fn(c)
        else:
            lo,c,fc = c,d,fd
            d=lo+g*(hi-lo);fd=fn(d)
    x=(lo+hi)/2
    return x,fn(x)


def root(fn, lo, hi):
    a=fn(lo)
    if a*fn(hi)>0:raise ValueError('Unbracketed contact')
    while hi-lo>0.002:
        mid=(lo+hi)/2
        if a*fn(mid)>0:lo=mid
        else:hi=mid
    return (lo+hi)/2


def sky_chart(eph,ts,p,terrain,when):
    cat=json.loads(CAT_PATH.read_text());t=ts.from_datetime(when)
    site=wgs84.latlon(p['lat'],p['lon'],elevation_m=p['elevation']+p.get('observingHeight',1.7))
    observer=(eph['earth']+site).at(t)
    stars=cat['stars']
    model=Star(ra_hours=np.array([s['ra'] for s in stars]),dec_degrees=np.array([s['dec'] for s in stars]),
               ra_mas_per_year=np.array([s['pmra'] for s in stars]),dec_mas_per_year=np.array([s['pmdec'] for s in stars]))
    alt,az,_=observer.observe(model).apparent().altaz()
    mask=combined_altitude(az.degrees,p.get('horizon',[]),terrain)
    rows=[{**s,'el':float(el),'az':float(a),'clear':bool(el>h)} for s,el,a,h in zip(stars,alt.degrees,az.degrees,mask) if el>=0]
    objects=[]
    for key,label in [('sun','Sun'),('moon','Moon'),('mercury','Mercury'),('venus','Venus'),('mars barycenter','Mars'),('jupiter barycenter','Jupiter'),('saturn barycenter','Saturn')]:
        el,a,_=observer.observe(eph[key]).apparent().altaz()
        if el.degrees>=0:objects.append({'name':label,'el':float(el.degrees),'az':float(a.degrees),'clear':bool(el.degrees>combined_altitude(a.degrees,p.get('horizon',[]),terrain))})
    return {'stars':rows,'lines':cat['lines'],'objects':objects,'horizon':[float(x) for x in combined_altitude(np.arange(360),p.get('horizon',[]),terrain)],
            'sunAltitude':float(observer.observe(eph['sun']).apparent().altaz()[0].degrees),
            'basis':'Zenith-centred equidistant chart, looking up: north top, east left. Geometric horizon with saved manual/terrain obstructions. No refraction; apparent star directions with catalogue proper motion. Bright-star orientation, not telescope pointing or a visibility forecast.'}


def polar(eph,ts,p,when,terrain=None):
    north=p['lat']>=0
    cat=json.loads(CAT_PATH.read_text())
    reference=cat['polarNorth' if north else 'polarSouth']
    star=Star(ra_hours=reference['ra'],dec_degrees=reference['dec'],ra_mas_per_year=reference['pmra'],dec_mas_per_year=reference['pmdec'])
    t=ts.from_datetime(when)
    site=wgs84.latlon(p['lat'],p['lon'],elevation_m=p['elevation']+p.get('observingHeight',1.7))
    apparent=(eph['earth']+site).at(t).observe(star).apparent()
    # Date-of-observation equator, not J2000: Polaris has moved with precession.
    ra,dec,_=apparent.radec(epoch=t)
    hour=(t.gast+p['lon']/15-ra.hours)*15%360
    offset=90-abs(dec.degrees)
    # Tangent-plane x towards east when looking at the pole, y towards zenith.
    el,az,_=apparent.altaz()
    da=math.radians(az.degrees-(0 if north else 180))
    h=math.radians(el.degrees);pole=math.radians(abs(p['lat']))
    dot=math.sin(h)*math.sin(pole)+math.cos(h)*math.cos(pole)*math.cos(da)
    x=math.degrees(math.atan2(-math.cos(h)*math.sin(da),dot))
    y=math.degrees(math.atan2(math.sin(h)*math.cos(pole)-math.cos(h)*math.sin(pole)*math.cos(da),dot))
    return {'north':north,'reference':reference['name'],'poleAltitude':abs(p['lat']),'bearing':0 if north else 180,
            'offset':offset,'hourAngle':hour,'x':x,'y':y,'starAltitude':float(el.degrees),'starAzimuth':float(az.degrees),
            'nearEquator':abs(p['lat'])<5,
            'referenceClear':bool(el.degrees>combined_altitude(az.degrees,p.get('horizon',[]),terrain)),
            'basis':'True celestial pole; naked-eye upright sky orientation, up toward zenith and east left when facing north (east right facing south). Not an optical reticle: scopes can invert/rotate. Follow the mount manual. Level mount, set latitude, aim tracking axis at true pole; magnetic north/south differs. Polaris / Sigma Octantis is offset from the pole. Southern reference is faint. No plate solving or mechanical control.'}


def live_positions(rows,ts,eph,p,when):
    by=station_rows(rows,ts);site=wgs84.latlon(p['lat'],p['lon'],elevation_m=p['elevation']+p.get('observingHeight',1.7))
    t=ts.from_datetime(when);out=[]
    sunalt=float((eph['earth']+site).at(t).observe(eph['sun']).apparent().altaz()[0].degrees)
    for number,row in by.items():
        age=(when-utc(row['EPOCH'])).total_seconds()/3600
        r={'name':STATIONS[number],'epoch':iso(utc(row['EPOCH'])),'ageHours':age,'usable':-6<=age<=48}
        if r['usable']:
            sat=EarthSatellite.from_omm(ts,row);pos=sat.at(t)
            if pos.message: r['usable']=False
            else:
                sub=wgs84.subpoint_of(pos);el,az,dist=(sat-site).at(t).altaz()
                track_t=ts.from_datetimes([when+timedelta(seconds=s) for s in range(-2700,2701,30)])
                track_pos=sat.at(track_t);track_sub=wgs84.subpoint_of(track_pos)
                r['track']=[[float(lon),float(lat)] for lon,lat in zip(track_sub.longitude.degrees,track_sub.latitude.degrees)]
                r.update(lat=float(sub.latitude.degrees),lon=float(sub.longitude.degrees),el=float(el.degrees),az=float(az.degrees),slant=float(dist.km),sunlit=bool(pos.is_sunlit(eph)),skyDark=sunalt<=-6)
        out.append(r)
    return {'stations':out,'observer':{'lat':p['lat'],'lon':p['lon']},'basis':'Calculated SGP4 positions, not live telemetry. Refreshed every 10 seconds while this view is open. Elements older than 48 h or >6 h in the future are withheld. Above the horizon does not mean visible; weather and obstructions remain separate.'}


def transit_geometry(sat,site,observer,eph,ts,target,dates):
    t=ts.from_datetimes(dates)
    # Consistent apparent topocentric rays; include light travel time and aberration.
    at=observer.at(t)
    s=at.observe(eph['earth']+sat).apparent()
    b=at.observe(eph[target]).apparent()
    sep=separation(s.position.au,b.position.au)
    radius=np.degrees(np.arcsin(RADII[target]/b.distance().km))
    el,az,dist=s.altaz()
    return sep,radius,el.degrees,az.degrees,dist.km


def search_transits(rows,ts,eph,p,terrain,when,hours=24):
    """24-hour, exact-site candidates + close approaches within 2 degrees.

    All above-horizon intervals sampled at <=2 s, every local angular minimum
    refined to 2 ms numerical tolerance. Model precision is NOT orbit accuracy.
    """
    site=wgs84.latlon(p['lat'],p['lon'],elevation_m=p['elevation']+p.get('observingHeight',1.7));observer=eph['earth']+site
    out=[];skipped=[];stop=when+timedelta(hours=hours)
    for number,row in station_rows(rows,ts).items():
        epoch=utc(row['EPOCH']);sat=EarthSatellite.from_omm(ts,row)
        if not -1<=(when-epoch).total_seconds()/3600<=24:
            skipped.append(STATIONS[number]+': elements outside −1 to +24 h age; refresh orbital data in Settings.');continue
        end=min(stop,epoch+timedelta(hours=24))
        skipped.append(STATIONS[number]+': search through '+iso(end)+' only (24 h element-age cutoff).')
        for rise,setting in pass_ranges(sat,site,ts,when,end):
            span=(setting-rise).total_seconds()
            if span<1:continue
            offsets=np.linspace(0,span,math.ceil(span/2)+1)
            dates=[rise+timedelta(seconds=float(v)) for v in offsets]
            for target in RADII:
                vals=transit_geometry(sat,site,observer,eph,ts,target,dates)
                sep,rad,el,az,dist=vals
                for i in range(1,len(offsets)-1):
                    if not(sep[i]<=sep[i-1] and sep[i]<sep[i+1]) or sep[i]>4:continue
                    def calc(s):return transit_geometry(sat,site,observer,eph,ts,target,[rise+timedelta(seconds=float(s))])
                    x,_=minimise(lambda s:float(calc(s)[0][0]),float(offsets[i-1]),float(offsets[i+1]))
                    se,r,e,a,d=[float(v[0]) for v in calc(x)]
                    if se>2 or e<5 or e<=combined_altitude(a,p.get('horizon',[]),terrain):continue
                    center=rise+timedelta(seconds=x)
                    disc=se<r;duration=None;ingress=None;egress=None
                    # Treat station as point; physical silhouette is not resolved.
                    if disc:
                        f=lambda s:float(calc(s)[0][0]-calc(s)[1][0])
                        if f(max(0,x-5))>0 and f(min(span,x+5))>0:
                            first=root(f,max(0,x-5),x);last=root(f,x,min(span,x+5))
                            ingress=stamp(rise+timedelta(seconds=first));egress=stamp(rise+timedelta(seconds=last));duration=last-first
                    out.append({'station':STATIONS[number],'target':target.title(),'time':stamp(center),
                        'localTime':center.astimezone(ZoneInfo(p.get('timezone','UTC'))).isoformat(timespec='milliseconds'),
                        'ingress':ingress,'egress':egress,'duration':duration,
                        'separation':se,'radius':r,'disc':disc,'el':e,'az':a,'rangeKm':d,'epoch':iso(epoch),
                        'ageHours':(center-epoch).total_seconds()/3600,'status':'UNCONFIRMED · model disc crossing' if disc else 'Close approach only · no model crossing',
                        'uncertainty':'Public GP orbits can be wrong by kilometres, even at epoch. No calibrated timing error or reliable ground corridor is available. Recheck against an independent transit service and fresh elements before travelling or observing.'})
    return {'events':sorted(out,key=lambda r:r['time']),'coverage':skipped,'until':iso(stop),
            'basis':'Exact selected site only, next up to 24 h, fresh elements only, above 5° and saved horizon. Nearby approaches within 2° shown separately. Point-station model against apparent Sun/Moon discs; no station silhouette, refraction, clouds or reliable corridor. Millisecond output is numerical precision, not a timing guarantee. No candidates does not prove no transit elsewhere.',
            'safety':'SOLAR SAFETY: Never look at the Sun through unfiltered binoculars, a telescope or a camera. Use appropriate purpose-made filters secured over the FRONT of every optical instrument, following manufacturer guidance. Eclipse glasses alone are NOT safe through optics. No equipment preference certifies solar safety.'}


def build(request,state,fixture=False):
    kind=request.get('kind','chart')
    if kind not in ('chart','polar','live','transits'):raise ValueError('Unknown view')
    p,terrain=point(request.get('source','active'),fixture)
    now=utc(request.get('fixtureNow') or '2026-11-09T00:00:00Z') if fixture else datetime.now(UTC)
    when=utc(request['time']) if request.get('time') and kind in ('chart','polar') else now
    if not 2000<=when.year<=2050:raise ValueError('Choose a time from 2000 to 2050')
    rows=read(ROOT/'tests/fixtures/stations.json',[]) if fixture else read(state/'orbit.json',{}).get('data',[])
    ts=load.timescale(builtin=True)
    with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
        if kind=='chart':
            when=now if request.get('satellites') is True else when
            data=sky_chart(eph,ts,p,terrain,when)
            if request.get('satellites') is True:
                from observatory.final_sky.satellite_layer import cached_rows,calculate
                cached,catalog=cached_rows(state,fixture,ROOT)
                data['satellites']=calculate(cached,catalog,ts,eph,p,terrain,when)
        elif kind=='polar':data=polar(eph,ts,p,when,terrain)
        elif not rows:data={'stations':[],'events':[],'basis':'No cached orbital elements. Opt into orbital downloads in Settings.'}
        elif kind=='live':data=live_positions(rows,ts,eph,p,when)
        else:data=search_transits(rows,ts,eph,p,terrain,when)
    return {**data,'kind':kind,'generated':iso(now),'time':stamp(when),'localTime':when.astimezone(ZoneInfo(p['timezone'])).isoformat(timespec='seconds'),'zone':p['timezone'],'source':request.get('source','active'),'place':p['name'],'fixture':fixture}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--state',type=Path,required=True);parser.add_argument('--fixture',action='store_true');args=parser.parse_args()
    try:
        raw=sys.stdin.buffer.read(4097)
        if len(raw)>4096:raise ValueError('Request too large')
        req=json.loads(raw)
        if not isinstance(req,dict):raise ValueError('Request must be an object')
        print(json.dumps(build(req,args.state,args.fixture),allow_nan=False))
    except (OSError,ValueError,TypeError,KeyError,OverflowError):
        print('Sky calculation unavailable. Check selected location, time, saved terrain and cached orbital elements. Existing data retained.',file=sys.stderr);return 1
    return 0

if __name__=='__main__':raise SystemExit(main())
