"""Explicit maintainer refresh; never runs as part of the user worker.

Fetch geocentric JPL tracks (no observing coordinates) and dated COBS estimates.
Use --output to stage a catalogue for review before shipping it.
"""
import argparse
import csv
from datetime import datetime, timedelta, timezone
import io
import json
from math import isfinite
from pathlib import Path
import urllib.parse
import urllib.request

TARGETS = (("161P/Hartley-IRAS", "90001108;", 393),
           ("10P/Tempel", "90000214;", 53),
           ("C/2026 A2 (Bok)", "90004959;", 2723),
           ("220P/McNaught", "90001188;", 130))


def fetch(url, params):
    request = urllib.request.Request(url + '?' + urllib.parse.urlencode(params),
                                     headers={'User-Agent': 'OMANOVA catalogue maintenance'})
    with urllib.request.urlopen(request, timeout=45) as response:
        raw = response.read(4_000_001)
    if len(raw) > 4_000_000:
        raise ValueError('Provider response exceeded size limit')
    return json.loads(raw)


def track(payload, start, end):
    text = payload.get('result', '')
    if payload.get('error') or '$$SOE' not in text or '$$EOE' not in text:
        raise ValueError('Horizons returned no unambiguous ephemeris')
    rows = list(csv.reader(io.StringIO(text.split('$$SOE')[1].split('$$EOE')[0].strip())))
    expected = int((end-start).total_seconds() // 7200) + 1
    if len(rows) != expected:
        raise ValueError('Horizons coverage is incomplete')
    values = []
    for i, row in enumerate(rows):
        stamp = datetime.strptime(row[0].strip(), '%Y-%b-%d %H:%M').replace(tzinfo=timezone.utc)
        coords = [float(x) for x in row[3:7]]
        if stamp != start + timedelta(hours=i*2) or len(coords) != 4 or not all(map(isfinite, coords)):
            raise ValueError('Unexpected Horizons timestamp or coordinates')
        if not all(0 <= coords[k] < 360 for k in (0, 2)) or not all(-90 <= coords[k] <= 90 for k in (1, 3)):
            raise ValueError('Horizons coordinate out of range')
        values.append(coords)
    return values


def magnitude(payload, now):
    if payload.get('signature', {}).get('version') not in ('1.4', '1.5'):
        raise ValueError('Unsupported COBS API version')
    rows = payload.get('objects', payload.get('object', []))
    valid=[]
    for row in rows:
        try:
            stamp=datetime.fromisoformat(row['obs_date']).replace(tzinfo=timezone.utc)
            mag=float(row['magnitude'])
            if not isfinite(mag) or not -10 <= mag <= 30 or not now-timedelta(days=21) <= stamp <= now:
                continue
            if row.get('conditions') == ':' or row.get('comet_visibility') in ('[', '>'):
                continue
            valid.append((row['type'] == 'V', stamp, mag, row))
        except (KeyError, ValueError, TypeError):
            continue
    if not valid:
        raise ValueError('No recent qualified COBS magnitude; review target manually')
    visual, stamp, mag, row = max(valid, key=lambda v: (v[0],v[1]))
    return {'magnitude': mag, 'observed': stamp.date().isoformat(),
            'method': 'visual' if visual else 'CCD',
            'observer': row.get('observer',{}).get('icq_name',''),
            'magnitudeCaution': 'Dated estimate, not a guaranteed current brightness.'}


def build(start, end, now):
    result={'from':start.isoformat().replace('+00:00','Z'),
            'until':end.isoformat().replace('+00:00','Z'), 'stepSeconds':7200,
            'refreshed':now.isoformat().replace('+00:00','Z'),
            'positionSource':'https://ssd.jpl.nasa.gov/horizons/',
            'magnitudeSource':'https://cobs.si/', 'targets':[]}
    for name, command, cobs in TARGETS:
        p={'format':'json','COMMAND':repr(command),'OBJ_DATA':"'YES'",'MAKE_EPHEM':"'YES'",
           'EPHEM_TYPE':"'OBSERVER'",'CENTER':"'500@399'",'START_TIME':repr(start.strftime('%Y-%m-%d')),
           'STOP_TIME':repr(end.strftime('%Y-%m-%d')),'STEP_SIZE':"'2 h'",'QUANTITIES':"'1,2'",
           'ANG_FORMAT':"'DEG'",'CSV_FORMAT':"'YES'"}
        positions=track(fetch('https://ssd.jpl.nasa.gov/api/horizons.api',p),start,end)
        observations=fetch('https://cobs.si/api/obs_list.api',{'format':'json','id':cobs,
            'from_date':(now-timedelta(days=21)).strftime('%Y-%m-%d'),
            'exclude_faint':'true','exclude_not_accurate':'true','exclude_issue':'true'})
        result['targets'].append({'name':name,'cobs':cobs,'horizons':command,
            **magnitude(observations,now),'positions':positions})
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--start', required=True)
    parser.add_argument('--until', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args=parser.parse_args()
    start=datetime.fromisoformat(args.start).replace(tzinfo=timezone.utc)
    end=datetime.fromisoformat(args.until).replace(tzinfo=timezone.utc)
    if not timedelta(days=1)<=end-start<=timedelta(days=45):
        parser.error('Stage between 1 and 45 days of coverage')
    result=build(start,end,datetime.now(timezone.utc))
    with args.output.open('x') as stream:
        json.dump(result,stream,indent=2);stream.write('\n')
    print('Staged',len(result['targets']),'targets through',result['until'])
