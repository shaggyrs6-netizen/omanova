"""Shared, local event catalogue and transparent next-opportunity ranking.

Geometry is cached separately from forecasts; weather and expiry are reassessed
on every worker refresh. Missing local visibility is never a recommendation.
"""
import argparse
from contextlib import closing
from datetime import datetime, timedelta, timezone
import fcntl
import hashlib
import json
from pathlib import Path
import sys

from astronomy import iso, utc
from conditions import classify, weather_hours
from observing_preferences import preferences
from worker import ROOT, DEMO_NOW, location, read, settings_at, write, forecast_key

RARITY = {'station':8,'satellite':4,'moon':3,'meteor':12,'planet':2,
          'conjunction':14,'comet':8,'eclipse':30,'launch':0,'plume':15,'train':12,'aurora':18}
PAGES = {'station':1,'satellite':11,'moon':5,'meteor':6,'planet':7,'conjunction':7,
         'comet':8,'eclipse':9,'launch':3,'plume':10,'train':12,'aurora':13}


def stamp(value):
    return value.get('time') if isinstance(value,dict) else value


def point(value):
    value=value if isinstance(value,dict) else {}
    return {'time':value.get('time') or value.get('highest'),
            'az':value.get('az',value.get('azimuth',value.get('bearing'))),
            'el':value.get('el',value.get('altitude',value.get('elevation'))),
            'direction':value.get('direction')}


def event(kind, name, start, end, look=None, *, object_id=None, visibility='possible',
          source='', reason='', valid_until=None, safety='', station_id=None):
    start,end=stamp(start),stamp(end)
    if not start or not end or utc(end)<=utc(start): return None
    key=str(object_id or name)
    return {'id':hashlib.sha256((kind+'|'+key+'|'+start).encode()).hexdigest()[:24],
            'object_id':key,'kind':kind,'name':name,'start':start,'end':end,'look':point(look),
            'visibility':visibility,'source':source,'reason':reason,'valid_until':valid_until,
            'safety':safety,'page':PAGES[kind],'station_id':station_id}


def station_events(snapshot):
    rows=[]
    for station in snapshot.get('events',[]):
        if not station['windows']:
            rows.append(event('station', station['name']+' · geometric pass', station['start'],station['end'],station.get('culmination'),
                object_id=station['source_id'],visibility='unconfirmed',source=station.get('source','https://celestrak.org/'),
                reason='Above the horizon, but no sunlit dark-sky viewing window is established.',station_id=station['id']))
        for window in station['windows']:
            rows.append(event('station',station['name'],window['start'],window['end'],window['peak'],
                object_id=station['source_id'], visibility='stale' if station['confidence']=='Stale orbit' else 'possible',
                valid_until=iso(utc(station['element_epoch'])+timedelta(hours=72)),
                reason='Sunlit station against a sufficiently dark local sky; brightness is not guaranteed.',
                source=station.get('source','https://celestrak.org/'),station_id=station['id']))
    return [row for row in rows if row]


def assess(rows, snapshot, forecast, now, generated):
    prefs=preferences(snapshot.get('settings',{}))
    settings=snapshot.get('settings',{})
    place=snapshot.get('place')
    hours={}
    if place and forecast.get('key')==forecast_key(place):
        try: hours=weather_hours(forecast.get('data',{}))
        except (ValueError,TypeError,KeyError): pass
    output=[]
    for original in rows:
        if not original: continue
        row=dict(original)
        start,end=utc(row['start']),utc(row['end'])
        if end<=now: continue
        stale=not timedelta(0)<=now-utc(generated)<=timedelta(hours=2) or (row.get('valid_until') and now>utc(row['valid_until']))
        if stale: row['visibility']='stale'
        row['conditions']=classify({'start':{'time':iso(max(start,now))},'end':{'time':row['end']}},
            hours,forecast.get('fetched'),now,settings.get('weather') is True)
        altitude=row['look'].get('el')
        conditions=row['conditions']['label']
        parts={'rarity':RARITY[row['kind']], 'weather':{'Favourable':25,'Mixed':0,'Uncertain':-15,'Poor':-40}[conditions],
               'elevation':round(max(0,altitude or 0)/3,1),
               'time':round(-max(0,(start-now).total_seconds()/3600)*3,1),
               'happeningNow':5 if start<=now else 0,
               'briefWindow':25 if end-start<=timedelta(minutes=15) else 10 if end-start<=timedelta(hours=1) else 0}
        row['score_parts']=parts;row['score']=round(sum(parts.values()),1)
        look_current=not row['look'].get('time') or utc(row['look']['time'])>=now-timedelta(minutes=5)
        row['recommended']=(look_current and row['visibility']=='possible' and row['kind'] in prefs['interests']
            and start<=now+timedelta(hours=24) and conditions!='Poor'
            and altitude is not None and altitude>=prefs['minimum_elevation'])
        row['assessment']=('Data stale' if row['visibility']=='stale' else
            'Local visibility unconfirmed' if row['visibility']!='possible' else
            'Poor conditions' if conditions=='Poor' else
            'Potential viewing · weather uncertain' if conditions=='Uncertain' else 'Potential viewing · '+conditions.lower())
        output.append(row)
    output.sort(key=lambda row:(row['start'],row['name'],row['id']))
    best=sorted((row for row in output if row['recommended']),key=lambda row:(-row['score'],row['start'],row['id']))
    return output,best[0] if best else None


def build_geometry(state, snapshot, now, fixture):
    from skyfield.api import load,load_file
    from observatory.moon import moon
    from observatory.planets import planets
    from observatory.meteors import meteors
    from observatory.comets import comets
    from observatory.eclipses import eclipses
    from observatory.satellites import watchlist
    from observatory.events import launches
    from observatory.plumes import plumes
    from observatory.trains import trains
    from observatory.aurora import aurora
    cache=state/'planning';cache.mkdir(parents=True,exist_ok=True)
    place=snapshot.get('place');rows=[];issues=[]
    if not place:return rows,['Set an observing location']
    ts=load.timescale(builtin=True)
    limit=iso(now+timedelta(hours=2))
    def add(kind,name,w,look=None,**kwargs):
        row=event(kind,name,w['start'],w['end'],look or w,valid_until=kwargs.pop('valid_until',limit),**kwargs)
        if row:rows.append(row)
    with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
        data=moon.calculate(eph,ts,place,now)
        for w in data['nextWindows']:
            add('moon',data['phase']+' Moon',w,w['peak'],source='https://ssd.jpl.nasa.gov/',reason='Moon above 5° with Sun below −6°. Phase illumination is available in Moon.')
        for phase in data['phases']:
            if phase['name']=='Full Moon':continue
            add('moon',phase['name']+' · exact phase',{'start':phase['time'],'end':iso(utc(phase['time'])+timedelta(minutes=1))},
                visibility='unconfirmed',source='https://ssd.jpl.nasa.gov/',reason='Exact astronomical phase, not a local viewing window. See Moon for local rise/set.')
        full=data['full'];details=moon.full_moon_details(eph,ts,utc(full['time']))
        for w in full['windows']:
            add('moon',details['name']+' · '+details['size'],w,w['peak'],object_id='full-'+full['time'],source='https://ssd.jpl.nasa.gov/',reason='Local viewing window near exact full phase.')
        data=planets.calculate(eph,ts,place,now)
        for target in data['highlights']:
            for w in target['windows']:add('planet',target['name'],w,source='https://ssd.jpl.nasa.gov/',reason='Planet above 10° with Sun below −6°.')
        for target in data['pairings']:
            w=target['window']
            if w:add('conjunction',target['name'],w,w['positions'][0],source='https://ssd.jpl.nasa.gov/',reason='Both objects meet local height and darkness limits; see Planets for separation.')
        for target in meteors.calculate(eph,ts,place,now):
            if target['activeNow'] and not target['windows']:
                add('meteor',target['name']+' · activity continues',{'start':iso(now),'end':iso(utc(target['activeEnd']+'T00:00:00Z')+timedelta(days=1))},
                    visibility='unconfirmed',source=target['source'],reason='Active dates continue after peak; a current local viewing window has not been calculated.')
            for w in target['windows']:
                add('meteor',target['name'],w,{**w,'time':w['highest']},source=target['source'],reason='Dark sky and high radiant near peak. Meteors can appear across the sky. Moon '+str(w['illumination'])+'% lit.')
        data=comets.calculate(eph,ts,place,now,read(ROOT/('tests/fixtures/comets-20261109.json' if fixture else 'observatory/comets/catalog.json'),{}))
        if not data['available']: issues.append('Comet catalogue is outside its dated coverage')
        for target in data['targets']:
            for w in target['windows']:
                add('comet',target['name'],w,source='https://cobs.si/obs/comet/'+str(target['cobs'])+'/',
                    reason='Equipment: '+target['equipment']+'. Magnitude '+str(target['magnitude'])+' estimate dated '+target['observed']+'.',
                    valid_until=min(limit,data['until']))
        data=eclipses.calculate(eph,ts,place,now)
        for kind in ('solar','lunar'):
            for target in data[kind]:
                for w in target['visible']:
                    add('eclipse',target['kind'].title()+' '+kind+' eclipse',w,target['look'],source='https://science.nasa.gov/eclipses/',
                        safety='Never look at the Sun without appropriate certified solar viewing protection.' if kind=='solar' else '',
                        reason='Local horizon-clipped eclipse geometry; see Eclipses for contacts and safety.')
    def run(label, fn, path):
        try:fn();return read(path,{})
        except (OSError,ValueError,KeyError,TypeError):issues.append(label+' data unavailable');return {}
    data=run('Satellites',lambda:watchlist.prepare(cache/'satellites.json',cache/'satellites',fixture,state),cache/'satellites.json')
    for w in data.get('windows',[]):
        if w['number'] in (25544,48274):continue
        add('satellite',w['name'],w,w['peak'],object_id=w['number'],source=watchlist.SOURCE,
            visibility='possible' if w.get('brightnessKnown') else 'unconfirmed',
            valid_until=min(limit,iso(utc(w['epoch'])+timedelta(hours=72))),reason='Sunlit geometry. Brightness unknown for custom objects.' if not w.get('brightnessKnown') else 'Selected bright-object catalogue; brightness varies.')
    schedule=run('Launches',lambda:launches.prepare(cache/'launches',fixture,state),cache/'launches/launches.json')
    for launch in schedule.get('launches',[]):
        if launch['net']:
            add('launch',launch['name'],{'start':launch['net'],'end':iso(utc(launch['net'])+timedelta(hours=1))},object_id=launch['id'],visibility='unconfirmed',source=launch['source'],reason=launch['status']+' · local visibility unconfirmed; schedule precision: '+launch['precision'])
    data=run('Plumes',lambda:plumes.prepare(cache/'plumes.json',cache/'launches/launches.json',fixture,state),cache/'plumes.json')
    for launch in data.get('launches',[]):
        for w in launch['windows']:add('plume',launch['name'],w,w['highest'],object_id=launch['id'],source=launch.get('trackSource') or '',reason='Experimental: '+launch['reason'])
    data=run('Starlink',lambda:trains.prepare(cache/'trains.json',cache/'trains',fixture,state),cache/'trains.json')
    for batch in data.get('batches',[]):
        for w in batch.get('windows',[]):add('train',batch['name'],w,w['best'],source=batch.get('source','https://celestrak.org/'),reason='Experimental train geometry; individual brightness is not guaranteed.')
    data=run('Aurora',lambda:aurora.prepare(cache/'aurora.json',cache/'aurora',fixture,state),cache/'aurora.json')
    current=data.get('current',{})
    if current.get('valid') and current.get('look'):
        add('aurora','Aurora outlook',{'start':current['valid'],'end':iso(utc(current['valid'])+timedelta(minutes=10))},current['look'],
            visibility='possible' if current.get('verdict')=='possible' else 'unconfirmed',
            source='https://www.swpc.noaa.gov/',valid_until=iso(utc(current['valid'])+timedelta(minutes=10)),reason='Experimental near-term model sightline, not a guaranteed aurora sighting.')
    return rows,issues


def refresh(state,fixture=False):
    state=Path(state);snapshot=read(state/'snapshot.json',{})
    now=DEMO_NOW if fixture else datetime.now(timezone.utc)
    if not snapshot.get('place'):
        write(state/'planner.json',{'generated':iso(now),'location_id':None,'events':[],'featured':None,'issues':['Set an observing location']});return
    settings=settings_at(state)
    snapshot['settings']=settings
    active=location(settings)
    if not active or active['id'] != snapshot['place']['id']:
        return
    key=hashlib.sha256(json.dumps({'place':snapshot['place'],'preferences':preferences(settings),
        'consent':{k:settings[k] for k in ('online','weather','launches','aurora')},'fixture':fixture},sort_keys=True).encode()).hexdigest()
    cache=read(state/'planning-cache.json',{})
    if cache.get('key')!=key or not cache.get('generated') or not timedelta(0)<=now-utc(cache['generated'])<timedelta(minutes=5 if settings['aurora'] else 30):
        rows,issues=build_geometry(state,snapshot,now,fixture)
        cache={'key':key,'generated':iso(now),'events':rows,'issues':issues}
        write(state/'planning-cache.json',cache)
    # Station geometry always comes from the newest worker snapshot.
    station_fresh=fixture or timedelta(0)<=now-utc(snapshot['generated'])<timedelta(minutes=3)
    station_rows=station_events(snapshot)
    if not station_fresh:
        for row in station_rows:row['visibility']='stale'
    rows,featured=assess(station_rows+cache['events'],snapshot,read(state/'weather.json',{}),now,cache['generated'])
    latest=read(state/'snapshot.json',{})
    if (latest.get('place') or {}).get('id') != snapshot['place']['id'] or preferences(settings_at(state)) != preferences(settings):
        return
    write(state/'planner.json',{'schema_version':1,'generated':iso(now),'fixture':fixture,'location_id':snapshot['place']['id'],
        'geometry_generated':cache['generated'],'events':rows,'featured':featured,'issues':cache['issues']})


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--state',type=Path,required=True);p.add_argument('--fixture',action='store_true');a=p.parse_args()
    a.state.mkdir(parents=True,exist_ok=True)
    with (a.state/'planner.lock').open('a') as stream:
        try:fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:sys.exit(75)
        refresh(a.state,a.fixture)
