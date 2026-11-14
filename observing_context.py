"""Read-only adapters for equipment and horizon-clipped Trip Planner windows."""
from datetime import UTC,datetime,timedelta
import hashlib,json,os
from pathlib import Path
from astronomy import iso,utc
from worker import read
DATA=Path(os.environ.get('XDG_DATA_HOME') or Path.home()/'.local/share')

def equipment_profile():
    from observatory.equipment.equipment import profile
    path=Path(os.environ.get('OMANOVA_EQUIPMENT_STATE') or DATA/'omanova-equipment')/'profile.json'
    raw=read(path,None)
    if raw is None and path.exists():raise ValueError('Equipment profile unreadable; retain it for inspection')
    return profile(raw or {})

def match(row,p,now=None):
    from observatory.equipment.equipment import assess
    now=now or datetime.now(UTC)
    a=assess(row,p,now,iso(now))
    if a:
        details=[]
        for k,label in (('apertureMm','aperture mm'),('fieldOfViewDeg','field °'),('binocularMagnification','binocular ×')):
            if p.get(k) is not None:details.append(str(p[k])+' '+label)
        if p.get('cameraMode') not in (None,'unknown'):details.append('camera '+p['cameraMode'])
        if details:a['notes'].append('Instrument context: '+', '.join(details)+'. No sensitivity or detail guarantee inferred.')
    return a

def trip_signature(config,state):
    from observatory.trips.trips import validate_config
    from observatory.trips.terrain import load_profile
    c=validate_config(config);c['weather']=False
    layers={k:load_profile(c[k],state) if c[k]['useTerrain'] else None for k in ('home','destination')}
    return hashlib.sha256(json.dumps({'config':c,'terrain':layers},sort_keys=True,separators=(',',':')).encode()).hexdigest()

def trip_state():return Path(os.environ.get('OMANOVA_TRIP_STATE') or DATA/'omanova-trips')

def trip_events(source,now=None,state=None):
    """Consume explicit compared windows; never recompute or download implicitly."""
    from planner import event
    from observatory.trips.trips import validate_config,local_stamp
    now=now or datetime.now(UTC);state=state or trip_state()
    key={'trip-home':'home','trip-destination':'destination'}.get(source)
    if key is None:raise ValueError('Choose a Trip Planner column')
    config=validate_config(read(state/'trip.json',{}));comparison=read(state/'comparison.json',{})
    if comparison.get('configurationHash')!=trip_signature(config,state):raise ValueError('Trip settings/horizon changed or comparison needs updating. Save & compare nights in Trip Planner first.')
    point=comparison.get(key,{})
    generated=comparison.get('generated');rows=[]
    try:stale=not timedelta(0)<=now-utc(generated)<timedelta(hours=2)
    except (TypeError,ValueError,OverflowError):stale=True
    for night in point.get('nights',[]):
        for target in night.get('targets',[]):
            kind='moon' if target['name']=='Moon' else 'planet'
            for w in target.get('windows',[]):
                r=event(kind,target['name'],w['start']['utc'],w['end']['utc'],{'time':w['look']['utc'],'az':w['bearing'],'el':w['altitude'],'direction':w['direction']},object_id=source+':'+target['name'],
                    visibility='stale' if stale else 'possible',valid_until=iso(utc(generated)+timedelta(hours=2)),source='https://science.nasa.gov/skywatching/',reason='Trip Planner window clipped by saved manual obstructions and any enabled terrain. Recheck forecasts and local conditions.')
                if r:r['conditions']=w.get('conditions',{'label':'Uncertain'});r['recommended']=not stale and r['conditions'].get('label') not in ('Poor','Uncertain');rows.append(r)
    for w in point.get('stations',[]):
        r=event('station',w['name'],w['start']['utc'],w['end']['utc'],{'time':w['look']['utc'],'az':w['bearing'],'el':w['altitude'],'direction':w['direction']},object_id=source+':'+w['name'],visibility='stale' if stale else 'possible',
                valid_until=iso(utc(generated)+timedelta(hours=2)),source='https://celestrak.org/',reason=point.get('stationNote','')+' Manual/terrain horizon applied. Station weather not supplied by this comparison.')
        if r:r['conditions']={'label':'Uncertain','reason':'Recheck weather'};r['recommended']=False;rows.append(r)
    for r in rows:
        r['timeZone']=point['timezone'];r['displayStart']=local_stamp(utc(r['start']),point['timezone']);r['displayEnd']=local_stamp(utc(r['end']),point['timezone'])
    return {'events':rows,'generated':generated,'timeZone':point['timezone'],'context':source,'horizonApplied':True,
            'note':'Saved Trip Planner comparison; manual obstructions and enabled terrain applied. Moon/planets and covered station passes only. Recompare after location/date/horizon changes. Weather may be unavailable.',
            'configurationHash':comparison['configurationHash'],'nightStart':config['start']}
