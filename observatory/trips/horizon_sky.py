"""Calculate an offline skyline view at the selected observing point."""
import argparse
from contextlib import closing
from datetime import UTC, datetime, timedelta
import json
from pathlib import Path
import sys

import numpy as np
from skyfield.api import Star, load, load_file

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import DIRECTIONS, iso, utc
from observatory.final_sky.geometry import CAT_PATH, SKY_BODIES, chart_observer, star_model
from observatory.trips.terrain import combined_altitude, load_profile
from observatory.trips.trips import local_stamp, validate_place

SEARCH_HOURS = 48
PLOT_MINIMUM = -20
NAMED_STARS = {'Polaris', 'Sirius', 'Vega', 'Arcturus', 'Capella', 'Rigel', 'Betelgeuse',
               'Deneb', 'Altair', 'Antares', 'Aldebaran', 'Regulus', 'Spica', 'Fomalhaut'}


def position(observer, target):
    altitude, azimuth, _ = observer.observe(target).apparent().altaz()
    return altitude.degrees, azimuth.degrees


def next_clear(observer, ts, target, place, terrain, when):
    def clearance(instants):
        altitude, azimuth = position(observer.at(ts.from_datetimes(instants)), target)
        return altitude - combined_altitude(azimuth, place['horizon'], terrain)

    step = timedelta(minutes=2)
    times = [when + i * step for i in range(SEARCH_HOURS * 30 + 1)]
    clear = np.flatnonzero(clearance(times) > 0)
    if not clear.size or clear[0] == 0:
        return None
    lower, upper = times[clear[0] - 1], times[clear[0]]
    while upper - lower > timedelta(seconds=15):
        middle = lower + (upper - lower) / 2
        if clearance([middle])[0] > 0:
            upper = middle
        else:
            lower = middle
    return upper


def marker(name, altitude, azimuth, skyline, **extra):
    status = 'below' if altitude < 0 else 'blocked' if altitude <= skyline else 'clear'
    return {'name': name, 'el': round(float(altitude), 2), 'az': round(float(azimuth), 2) % 360,
            'direction': DIRECTIONS[int((azimuth + 11.25) // 22.5) % 16], 'status': status,
            'skyline': round(float(skyline), 2), **extra}


def calculate(eph, ts, place, terrain, when, selected):
    observer = chart_observer(eph, place)
    at = observer.at(ts.from_datetime(when))
    stars = [s for s in json.loads(CAT_PATH.read_text())['stars'] if s['mag'] <= 4]
    heights, bearings = position(at, star_model(stars))
    skyline = combined_altitude(bearings, place['horizon'], terrain)
    dots, picks, models = [], [], {}
    for star, height, bearing, edge in zip(stars, heights, bearings, skyline):
        named = star['name'] in NAMED_STARS
        if height >= PLOT_MINIMUM or named:
            row = marker(star['name'], height, bearing, edge, mag=star['mag'])
            if height >= PLOT_MINIMUM:
                dots.append(row)
            if named:
                picks.append(row)
                models[star['name']] = star

    objects = []
    for label, key in SKY_BODIES.items():
        height, bearing = position(at, eph[key])
        edge = combined_altitude(bearing, place['horizon'], terrain)
        objects.append(marker(label, height, bearing, edge))
    targets = objects + sorted(picks, key=lambda row: row['name'])
    chosen = next((item for item in targets if item['name'] == selected), objects[1])
    rise = None
    if chosen['status'] != 'clear':
        name = chosen['name']
        if name in SKY_BODIES:
            target = eph[SKY_BODIES[name]]
        else:
            star = models[name]
            target = Star(ra_hours=star['ra'], dec_degrees=star['dec'],
                          ra_mas_per_year=star['pmra'], dec_mas_per_year=star['pmdec'])
        rise = next_clear(observer, ts, target, place, terrain, when)
    return {'time': iso(when), 'localTime': local_stamp(when, place['timezone']),
            'stars': dots, 'objects': objects, 'targets': targets,
            'selected': chosen, 'nextClear': local_stamp(rise, place['timezone']) if rise else None,
            'sunAltitude': objects[0]['el'], 'terrainLoaded': terrain is not None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state', required=True, type=Path)
    args = parser.parse_args()
    raw = sys.stdin.buffer.readline(65537)
    if len(raw) > 65536 or not raw.endswith(b'\n'):
        raise ValueError('Expected one bounded sky request')
    request = json.loads(raw)
    place = validate_place(request['place'])
    when = utc(request['time'])
    if not 2000 <= when.year <= 2050 or abs(when - datetime.now(UTC)) > timedelta(days=2):
        raise ValueError('Choose a time within a day of now')
    terrain = load_profile(place, args.state)
    ts = load.timescale(builtin=True)
    with closing(load_file(str(ROOT / 'assets/de440s.bsp'))) as eph:
        print(json.dumps(calculate(eph, ts, place, terrain, when, request.get('selected')), allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError):
        sys.exit('Sky positions unavailable. Check the site and local astronomy runtime.')
