"""Bounded, network-free night strip from the current snapshot and cached kernel."""
import argparse
from contextlib import closing
from datetime import datetime, timedelta, UTC
import math
from pathlib import Path
import sys
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from astronomy import iso, utc
from conditions import dew_risk, optical_context, weather_hours
from worker import read, write, forecast_key, DEMO_NOW
from observatory.trips.trips import night_bounds, system_zone


def cached_clouds(state, snapshot, now):
    if snapshot.get('settings', {}).get('weather') is not True:
        return {}, None, 'Weather downloads are off; cloud cover unknown.'
    cache = read(state / 'weather.json', {})
    try:
        fetched = utc(cache['fetched'])
        if cache.get('key') != forecast_key(snapshot['place']) or not timedelta(0) <= now-fetched < timedelta(hours=6):
            raise ValueError('Expired or mismatched forecast')
        return weather_hours(cache['data']), iso(fetched), 'Cached hourly cloud cover; gaps stay unknown.'
    except (KeyError, ValueError, TypeError, OverflowError):
        return {}, None, 'Forecast missing, expired or for another location; cloud cover unknown.'


def build(state, snapshot, now=None):
    from skyfield.api import load, load_file, wgs84
    from skyfield import almanac
    now = now or (DEMO_NOW if snapshot.get('demo') is True else datetime.now(UTC))
    place = snapshot.get('place')
    if not place:
        raise ValueError('Set an observing location to see the night strip.')
    zone = system_zone()
    local = now.astimezone(ZoneInfo(zone))
    ts = load.timescale(builtin=True)
    with closing(load_file(str(ROOT / 'assets/de440s.bsp'))) as eph:
        observer = eph['earth'] + wgs84.latlon(place['lat'], place['lon'], elevation_m=place['elevation'])
        current_time = ts.from_datetime(now)
        sun_now = observer.at(current_time).observe(eph['sun']).apparent().altaz()[0].degrees
        moon_fraction = float(almanac.fraction_illuminated(eph, 'moon', current_time))
        moon_waxing = bool(almanac.moon_phase(eph, current_time).degrees < 180)
        day = local.date() - timedelta(days=int(local.hour < 12 and sun_now < -6))
        start, end = night_bounds(day, zone)
        stamps = []
        at = start
        while at < end:
            stamps.append(at)
            at += timedelta(hours=1)
        times = ts.from_datetimes(stamps)
        sun = observer.at(times).observe(eph['sun']).apparent().altaz()[0].degrees
        moon = observer.at(times).observe(eph['moon']).apparent().altaz()[0].degrees
        forecast, fetched, note = cached_clouds(state, snapshot, now)
        rows = []
        for stamp, alt, lunar in zip(stamps, sun, moon):
            hour = stamp.replace(minute=0, second=0, microsecond=0)
            weather = forecast.get(hour, {})
            rows.append({'time':iso(stamp), 'label':stamp.astimezone(ZoneInfo(zone)).strftime('%H:%M'),
                         'light':'daylight' if alt >= 0 else 'twilight' if alt > -18 else 'dark',
                         'moonUp': bool(lunar > 0), 'cloud': weather.get('cloud_cover'),
                         'dewRisk': dew_risk(weather)})
        t, up = almanac.find_discrete(ts.from_datetime(start), ts.from_datetime(end),
                                     almanac.sunrise_sunset(eph, wgs84.latlon(place['lat'], place['lon'], elevation_m=place['elevation'])))
        rises = [iso(v.utc_datetime()) for v, state in zip(t, up) if state]
        sets = [iso(v.utc_datetime()) for v, state in zip(t, up) if not state]
    hour = now.replace(minute=0, second=0, microsecond=0)
    quality = [{'time': iso(stamp), 'label': stamp.astimezone(ZoneInfo(zone)).strftime('%a %H:%M %Z'),
                **optical_context(forecast.get(stamp, {}))}
               for stamp in (hour + timedelta(hours=i) for i in range(24))] if fetched else []
    return {'location_id':place['id'], 'generated':iso(now), 'night':str(day), 'zone':zone,
            'start':iso(start), 'end':iso(end), 'sunset':sets[0] if sets else None,
            'sunrise':rises[0] if rises else None, 'hours':rows,
            'weatherFetched':fetched, 'weatherNote':note, 'opticalHours':quality,
            'moonFraction':moon_fraction, 'moonWaxing':moon_waxing,
            'basis':'Hourly Sun/Moon geometry and cached weather, not a visibility score. Active-location horizons are not applied to this strip.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        snapshot = read(args.state/'snapshot.json', {})
        write(args.output, build(args.state, snapshot))
    except (OSError, ValueError, TypeError, KeyError, OverflowError):
        print('Night strip unavailable. Check location, cached forecast and local ephemeris.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
