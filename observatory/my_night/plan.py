"""A private observing list and local timing estimates. No network or alerts."""
import argparse
from contextlib import closing
from datetime import UTC, date, datetime, timedelta
import hashlib
import json
import math
import os
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import DIRECTIONS, iso, utc
from observing_context import trip_state
from observatory.equipment.equipment import clean_row
from observatory.field.field import CAT, point
from observatory.night_context import cached_clouds
from observatory.offline import offline
from observatory.trips.horizon import place_key
from observatory.trips.terrain import combined_altitude
from observatory.trips.trips import local_stamp, night_bounds, system_zone
from worker import DEFAULT_STATE, DEMO_NOW, forecast_key, location, lock, read, settings_at, write
from conditions import weather_hours

SOURCES = ('active', 'trip-home', 'trip-destination')
PLANETS = {'Mercury':'mercury', 'Venus':'venus', 'Mars':'mars barycenter',
           'Jupiter':'jupiter barycenter', 'Saturn':'saturn barycenter'}
TARGETS = {t['id']: {**t, 'kind': kind} for kind, entries in
           (('landmark', CAT['landmarks']), ('deep-sky', CAT['targets'])) for t in entries}
TARGETS.update({name: {'name': name, 'body': body, 'kind': 'planet',
                      'source': 'https://ssd.jpl.nasa.gov/'} for name, body in PLANETS.items()})
LIMIT = 24


def checked_night(value):
    day = date.fromisoformat(value)
    if value != day.isoformat() or not 2000 <= day.year <= 2050:
        raise ValueError('Enter a night as YYYY-MM-DD (2000–2050).')
    return day


def fresh(value, now, seconds):
    try:
        return timedelta(0) <= now - utc(value) <= timedelta(seconds=seconds)
    except (ValueError, TypeError, AttributeError, OverflowError):
        return False


def timing_sample(at, el, az, horizon, sun):
    return {'time': iso(at), 'el': round(float(el), 2), 'az': round(float(az) % 360, 2),
            'horizon': round(float(horizon), 2), 'sun': round(float(sun), 2)}


def windows(points, min_el, sun_limit):
    """Return contiguous runs of passing samples without bridging blocked gaps."""
    result, run = [], []
    for sample in [*points, None]:
        if (sample is not None and sample['el'] >= min_el and
                sample['el'] > sample['horizon'] and sample['sun'] <= sun_limit):
            run.append(sample)
        else:
            if len(run) >= 2:
                result.append((run[0], max(run, key=lambda row: row['el']), run[-1]))
            run = []
    return result


def sample_times(start, end, step):
    count = math.ceil((end-start)/step)
    return [start+min(step*i, end-start) for i in range(count+1)]


def profile(eph, ts, site, times):
    t = ts.from_datetimes(times)
    obs = (eph['earth']+site).at(t)
    sun = obs.observe(eph['sun']).apparent().altaz()[0].degrees
    return obs, sun


def target_chart(key, place, terrain, start, end, now, eph, ts, site):
    from skyfield.api import Star
    spec = TARGETS[key]
    times = sample_times(start, end, timedelta(minutes=5))
    obs, sun = profile(eph, ts, site, times)
    body = eph[spec['body']] if 'body' in spec else Star(ra_hours=spec['ra'], dec_degrees=spec['dec'])
    el, az, _ = obs.observe(body).apparent().altaz()
    horizon = combined_altitude(az.degrees, place.get('horizon', []), terrain)
    points = [timing_sample(*values) for values in zip(times, el.degrees, az.degrees, horizon, sun)]
    min_el = 10 if spec['kind']=='planet' else 20
    sun_limit = -18 if spec['kind']=='deep-sky' else -6
    runs = windows(points, min_el, sun_limit)
    upcoming = windows([row for row in points if utc(row['time']) >= now], min_el, sun_limit)
    chosen = max(upcoming or runs, key=lambda run: run[1]['el'], default=None)
    row = None
    if chosen:
        a, b, c = chosen
        row = {'id': 'target-'+key, 'kind': spec['kind'], 'name': spec['name'],
               'start': a['time'], 'end': c['time'], 'look': {**b, 'direction': DIRECTIONS[int((b['az']+11.25)//22.5)%16]},
               'visibility': 'unconfirmed', 'source': spec.get('source', CAT['coordinateSource']),
               'reason': 'Calculated geometry. '+spec.get('hint', '')}
    note = f'5-minute samples · at least {min_el}° up · Sun at or below {sun_limit}° · saved horizon applied.'
    return points, row, note, bool(upcoming)


def snapshot_context(data, now, fixture):
    settings = settings_at(data)
    snapshot = read(data/'snapshot.json', {})
    planner = read(data/'planner.json', {})
    active = snapshot.get('place') if fixture else location(settings)
    matching = bool(active and snapshot.get('place') and
                    active['id']==snapshot['place']['id'] and
                    place_key(active)==place_key(snapshot['place']) and
                    planner.get('location_id')==active['id'])
    current = matching and (fixture or (
        not snapshot.get('demo') and fresh(snapshot.get('generated'), now, 180) and
        fresh(planner.get('generated'), now, 180)))
    return settings, snapshot, planner, active, current


def event_chart(pick, context, place, start, end, now, fixture, terrain, eph, ts, site):
    _, snapshot, planner, active, current = context
    saved = pick['event']
    match_place = place_key(place)==pick['site']
    matching_context = active and place_key(active)==pick['site']
    latest = next((r for r in planner.get('events', []) if r.get('id')==saved['id']), None) if matching_context else None
    entry = clean_row(latest) or saved
    expires = entry.get('valid_until')
    stale = (not current or not latest or entry['visibility']=='stale' or
             (bool(expires) and utc(expires)<=now))
    row_start, row_end = max(start,utc(entry['start'])), min(end,utc(entry['end']))
    if not match_place or row_start>=row_end:
        return [], None, ('Saved event is for another location.' if not match_place else
                          'Saved event falls outside this night.'), False
    row = {**entry, 'start': iso(row_start), 'end': iso(row_end)}
    points = []
    note = 'Source window only. No continuous altitude data for this event.'
    eligible = not stale and utc(entry['start'])>=start and row_end>now
    if entry['kind']=='station':
        station = next((r for r in snapshot.get('events',[]) if r.get('id')==pick.get('station')), None) if matching_context else None
        orbit_fresh = bool(station and station.get('confidence')!='Stale orbit' and
                           -6 <= (now-utc(station['element_epoch'])).total_seconds()/3600 <=48)
        track = [s for s in (station or {}).get('path', []) if start<=utc(s['time'])<=end]
        if track:
            _, sun = profile(eph, ts, site, [utc(s['time']) for s in track])
            horizons = combined_altitude([s['az'] for s in track], place.get('horizon',[]), terrain)
            points = [timing_sample(utc(s['time']),s['el'],s['az'],h,d) for s,h,d in zip(track,horizons,sun)]
            clipped = [p for p in points if row_start<=utc(p['time'])<=row_end and utc(p['time'])>=now]
            potential = entry['visibility']=='possible' and not stale and orbit_fresh
            runs = windows(clipped,10 if potential else 0,-6 if potential else 90)
            best = max(runs,key=lambda run:run[1]['el'],default=None)
            if best:
                a,b,c=best
                row.update(start=a['time'],end=c['time'],look={**b,'direction':DIRECTIONS[int((b['az']+11.25)//22.5)%16]})
            if not potential:
                row['visibility'] = 'stale' if stale or not orbit_fresh else 'unconfirmed'
            eligible = eligible and bool(best)
            note = ('Potential viewing geometry · brightness and weather uncertain.' if potential else
                    'Geometric pass only · visibility unconfirmed.')
            if not best:
                note += ' No remaining segment clears the saved horizon.'
        else:
            note = 'Saved station window only. Pass path unavailable.'
            eligible = False
        stale |= not orbit_fresh
    if entry['kind']!='station' and row['look']['az'] is not None and row['look']['el'] is not None:
        if row['look']['el'] <= float(combined_altitude(row['look']['az'],place.get('horizon',[]),terrain)):
            note += ' Suggested direction is blocked by the saved horizon.'
            eligible = False
    if entry['kind']=='launch':
        note = 'Launch schedule only · local visibility unconfirmed.'
        eligible = False
    if stale:
        note = 'Stale or missing source · inspect only. '+note
    return points, row, note, eligible and not stale and row['look']['el'] is not None


def weather(data, context, place, source, now, fixture):
    settings, _, _, active, _ = context
    if fixture:
        return {}, None, 'Weather unknown in this sample.'
    if source=='active' or (active and place_key(place)==place_key(active)):
        return cached_clouds(data, {'settings': settings, 'place': place}, now)
    config = read(trip_state()/'trip.json', {})
    key = forecast_key(place)
    cache = read(trip_state()/('weather-'+hashlib.sha256(key.encode()).hexdigest()[:16]+'.json'), {})
    if config.get('weather') is True and fresh(cache.get('fetched'), now, 21600):
        try:
            return weather_hours(cache['data']),cache['fetched'],'Cached destination forecast.'
        except (KeyError, ValueError, TypeError):
            pass
    return {}, None, 'No fresh cached forecast for this destination.'


def get_point(source, fixture, active):
    if not fixture and source=='active' and not active:
        raise ValueError('Set an active location in Settings.')
    return point(source, fixture)


def build(plan, context, data, fixture, now, selected):
    source=plan['source']
    rows = [dict(id=p['id'], name=p['name'], kind=p['kind'],
                 extent=TARGETS.get(p['id'][2:], {}).get('extent') if p['kind']=='target' else None)
            for p in plan['picks']]
    frame = {'plan': plan, 'rows': rows, 'chart': None, 'error': '', 'zone': '',
             'catalogue': [dict(id=k,name=t['name']) for k,t in TARGETS.items()]}
    try:
        place, terrain = get_point(source, fixture, context[3])
    except (ValueError, OSError, TypeError, KeyError):
        frame['error'] = 'Location or saved terrain is unavailable. Check Settings or Trip Planner.'
        return frame, []
    from skyfield.api import load, load_file, wgs84
    zone = place['timezone']
    frame.update(zone=zone, place=place['name'])
    start,end = night_bounds(checked_night(plan['night']), zone)
    frame['period'] = local_stamp(start,zone)+' to '+local_stamp(end,zone)
    frame['checked'] = local_stamp(now,zone)
    if not rows:
        return frame,[]
    ts = load.timescale(builtin=True)
    site = wgs84.latlon(place['lat'],place['lon'],elevation_m=place['elevation']+place.get('observingHeight',1.7))
    clouds, fetched, weather_note = weather(data,context,place,source,now,fixture)
    eligible_rows = []
    with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
        for pick, summary in zip(plan['picks'],rows):
            if pick['kind']=='target':
                samples,row,note,eligible=target_chart(pick['id'][2:],place,terrain,start,end,now,eph,ts,site)
                if not row:
                    note = 'No window meets the height, darkness and horizon limits. '+note
                elif not eligible:
                    note = 'Window has ended or is too short to use from now. '+note
            else:
                samples,row,note,eligible=event_chart(pick,context,place,start,end,now,fixture,terrain,eph,ts,site)
            summary.update(logPlace=place['name'] if pick['kind']=='target' or place_key(place)==pick['site'] else '',
                           note=note, eligible=eligible, begin='', best='', end='', weather='Cloud cover unknown.')
            if row:
                if utc(row['end'])<=now and pick['kind']=='event':
                    summary['note'] = 'Ended window · inspect only. '+summary['note']
                summary.update(begin=local_stamp(utc(row['start']),zone),end=local_stamp(utc(row['end']),zone))
                look = row['look'] or {}
                if look.get('time') and utc(row['start'])<=utc(look['time'])<=utc(row['end']):
                    at=utc(look['time'])
                    summary['best']=local_stamp(at,zone)
                    if look.get('direction') and look.get('el') is not None:
                        summary['direction']=f"{look['direction']} · {look['el']:.0f}° up"
                    cloud=clouds.get(at.replace(minute=0,second=0,microsecond=0),{}).get('cloud_cover')
                    if cloud is not None:
                        summary['weather']=f'Cached area forecast at best time: {cloud:.0f}% cloud.'
                if eligible:
                    row.update(id=pick['id'],recommended=False,conditions={'label':'Uncertain','reason':summary['weather'],
                               'fetched':fetched if summary['weather'].startswith('Cached') else None})
                    row['reason'] = note+' '+summary['weather']+' '+row.get('reason','')
                    eligible_rows.append(row)
            if pick['id']==selected or (selected not in {p['id'] for p in plan['picks']} and frame['chart'] is None):
                a,b = (utc(samples[0]['time']),utc(samples[-1]['time'])) if samples and pick['kind']=='event' else (start,end)
                if row and pick['kind']=='event' and not samples:
                    a,b=max(start,utc(row['start'])-timedelta(minutes=20)),min(end,utc(row['end'])+timedelta(minutes=20))
                sun_times=sample_times(a,b,timedelta(minutes=5))
                _, sun = profile(eph,ts,site,sun_times)
                frame['chart']={'id':pick['id'],'points':samples,'start':iso(a),'end':iso(b),
                    'from':local_stamp(a,zone),'to':local_stamp(b,zone),'note':weather_note,
                    'dark':[{'time':iso(t),'dark':float(s)<=-18} for t,s in zip(sun_times,sun)],
                    'clouds':[{'time':iso(t),'value':values['cloud_cover']} for t,values in sorted(clouds.items())
                              if t<b and t+timedelta(hours=1)>a and values['cloud_cover'] is not None],
                    'window':[row['start'],row['end']] if row else [],'best':(row or {}).get('look',{}).get('time',''),
                    'ticks':[{'time':iso(a+(b-a)*i/4),'label':(a+(b-a)*i/4).astimezone(ZoneInfo(zone)).strftime('%H:%M')} for i in range(5)]}
    return frame,eligible_rows


def run(state,data,offline_state,fixture,request,now):
    context = snapshot_context(data,now,fixture)
    local = now.astimezone(ZoneInfo(system_zone()))
    default_night=(local.date()-timedelta(days=local.hour<12)).isoformat()
    with lock(state):
        plan = read(state/'plan.json', {'source':'active','night':default_night,'picks':[]})
        action=request.get('action','view')
        selected=request.get('selected','')
        if action=='configure':
            source=request.get('source')
            if source not in SOURCES:raise ValueError('Choose a location.')
            plan.update(source=source,night=checked_night(request['night']).isoformat())
        elif action=='add':
            kind=request.get('kind')
            key=request.get('key')
            if kind=='target' and key in TARGETS:
                item={'id':'t:'+key,'kind':'target','name':TARGETS[key]['name']}
            elif kind=='event':
                match=next((r for r in context[2].get('events',[]) if r.get('id')==key),None)
                event=clean_row(match)
                active=context[3]
                if (not event or not active or context[2].get('location_id')!=active['id'] or
                        not context[1].get('place') or place_key(context[1]['place'])!=place_key(active)):
                    raise ValueError('Event no longer matches the active location. Refresh Events and try again.')
                if event['kind']=='planet' and event['name'] in PLANETS:
                    item={'id':'t:'+event['name'],'kind':'target','name':event['name']}
                else:
                    item={'id':'e:'+event['id'],'kind':'event','name':event['name'],'site':place_key(active),
                          'station':match.get('station_id'),'event':event}
            else:
                raise ValueError('This target is not available.')
            selected=item['id']
            if not any(p['id']==selected for p in plan['picks']):
                if len(plan['picks'])>=LIMIT:raise ValueError('My Night holds up to 24 picks. Remove one before adding another.')
                plan['picks'].append(item)
        elif action=='remove':
            plan['picks']=[p for p in plan['picks'] if p['id']!=selected]
        elif action not in ('view','export'):
            raise ValueError('Unknown action.')
        if action in ('configure','add','remove'):
            write(state/'plan.json',plan)
        frame, eligible = build(plan,context,data,fixture,now,selected)
        frame['exportable'] = len(eligible)
        if action=='export':
            if not eligible:
                raise ValueError('No picks have a current, exportable window for this night.')
            source = ('sample' if fixture else 'live') if plan['source']=='active' else plan['source']
            deck = offline.prepare(offline_state, {'source':source,'zone':frame['zone'],'night':plan['night']},
                                   now,selected_source=(eligible,iso(now),now,[]))
            deck.update(myNight=True,displayMode=request.get('display') if request.get('display') in ('red','dim') else 'normal')
            deck['rows'] = [r for r in deck['rows'] if not r['unsupported'] and not r['staleAtCapture']]
            deck['available']=len(deck['rows'])
            if not deck['rows']:
                raise ValueError('No picks meet your saved equipment filters or guide freshness rules.')
            with lock(offline_state):
                guide,_=offline.persist(offline_state,deck,now)
            frame['guide']=str(offline_state/'guides'/guide/'guide.html')
            frame['savedCount']=len(deck['rows'])
        return frame


def main():
    parser=argparse.ArgumentParser()
    for arg in ('state','data','offline'):
        parser.add_argument('--'+arg,type=Path,required=True)
    parser.add_argument('--fixture',action='store_true')
    args=parser.parse_args()
    os.umask(0o077)
    if args.fixture:
        if not all(p.resolve().is_relative_to((ROOT/'.preview').resolve()) for p in (args.state,args.data,args.offline)):
            raise ValueError('Use isolated fixture directories.')
    elif (args.data.resolve()!=DEFAULT_STATE.resolve() or
          args.state.resolve()!=(DEFAULT_STATE.parent/'omanova-my-night').resolve() or
          args.offline.resolve()!=offline.LIVE_STATE.resolve()):
        raise ValueError('Use the dedicated My Night and Offline Cards directories.')
    raw=sys.stdin.buffer.readline(4097)
    if len(raw)>4096:
        raise ValueError('Request too large.')
    req=json.loads(raw)
    now=DEMO_NOW if args.fixture else datetime.now(UTC)
    print(json.dumps(run(args.state,args.data,args.offline,args.fixture,req,now),allow_nan=False))


if __name__=='__main__':
    try:
        main()
    except (OSError, KeyError, TypeError, OverflowError, ValueError) as exc:
        msg=str(exc) if isinstance(exc,ValueError) and str(exc).endswith('.') else 'My Night data unavailable. Check the night, location and saved horizon.'
        print(json.dumps({'failure':msg[:200]}))
        sys.exit(1)
