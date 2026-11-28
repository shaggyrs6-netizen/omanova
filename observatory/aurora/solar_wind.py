"""Bounded NOAA SWPC L1 context for the Aurora view."""
from datetime import timedelta
from math import isfinite
import re

from astronomy import iso, utc
from worker import get_json, lock, read, update_source, write

RTSW = 'https://services.swpc.noaa.gov/json/rtsw/'
FEEDS = {
    'plasma': ('rtsw_wind_1m.json', {'speed': ('proton_speed', 0, 5000),
                                    'density': ('proton_density', 0, 5000)}),
    'field': ('rtsw_mag_1m.json', {'bz': ('bz_gsm', -1000, 1000), 'bt': ('bt', 0, 1000)}),
}
MAX_AGE = timedelta(minutes=15)


def latest_active(data, fields, now):
    if not isinstance(data, list) or not 1 <= len(data) <= 12000:
        raise ValueError('Unexpected NOAA RTSW response')
    latest = None
    for row in data:
        if (not isinstance(row, dict) or row.get('active') is not True
                or type(row.get('overall_quality')) is not int or row['overall_quality'] != 0):
            continue
        source = row.get('source')
        if not isinstance(source, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,24}', source):
            continue
        try:
            observed = utc(row['time_tag'])
        except (KeyError, TypeError, ValueError):
            continue
        if not timedelta(0) <= now - observed < MAX_AGE or (latest and observed <= utc(latest['observed'])):
            continue
        values = {}
        for key, (field, lower, upper) in fields.items():
            value = row.get(field)
            if type(value) in (int, float) and lower <= value <= upper and isfinite(value):
                values[key] = value
        if values:
            latest = {'observed': iso(observed), 'source': source, **values}
    return latest


def sample(state, kind, now, enabled, fetch=get_json):
    product, fields = FEEDS[kind]

    def download():
        data = fetch(RTSW + product, max_bytes=5_000_000)
        return latest_active(data, fields, now)

    with lock(state):
        path = state / f'solar-wind-{kind}.json'
        cache = read(path, {})
        if not isinstance(cache, dict):
            cache = {}
        before = cache.copy()
        if enabled:
            update_source(cache, now, timedelta(minutes=5), download, lambda _: None)
        if cache != before:
            write(path, cache)
    row = cache.get('data')
    try:
        current = row if isinstance(row, dict) and timedelta(0) <= now - utc(row['observed']) < MAX_AGE else None
    except (KeyError, TypeError, ValueError):
        current = None
    return current, bool(cache.get('error'))


def context(state, now, enabled, fixture=False):
    if fixture:
        return {'plasma': {'observed': iso(now - timedelta(minutes=3)), 'source': 'Sample',
                           'speed': 572.4, 'density': 6.8},
                'field': {'observed': iso(now - timedelta(minutes=2)), 'source': 'Sample',
                          'bz': -8.2, 'bt': 11.7}, 'fetchIssue': False}
    plasma, plasma_error = sample(state, 'plasma', now, enabled)
    field, field_error = sample(state, 'field', now, enabled)
    return {'plasma': plasma, 'field': field, 'fetchIssue': plasma_error or field_error}
