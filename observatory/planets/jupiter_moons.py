"""Approximate Galilean moon and shadow windows with local observing geometry."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import sys

import numpy as np
from pymeeus.Epoch import Epoch
from pymeeus.JupiterMoons import JupiterMoons
from skyfield.api import load, load_file, wgs84

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import iso, utc
from observatory.field.field import point
from observatory.moon.moon import intervals
from observatory.planets.planets import describe, samples
from observatory.trips.terrain import combined_altitude
from worker import write

MOONS = ("Io", "Europa", "Ganymede", "Callisto")
KINDS = ("Moon transit", "Shadow transit")


def geometry(when):
    epoch = Epoch(when.year, when.month, when.day, when.hour, when.minute,
                  when.second + when.microsecond / 1e6, utc=True)
    # PyMeeus uses negative Earth/Sun-view z for a moon in the foreground.
    # The shadow's centre is approximated by the solar-view projection.
    earth = JupiterMoons.rectangular_positions_jovian_equatorial(epoch)
    sun = JupiterMoons.rectangular_positions_jovian_equatorial(epoch, solar=True)
    return tuple(z < 0 and JupiterMoons.check_coordinates(x, y) <= 1
                 for view in (earth, sun) for x, y, z in view)


def refine(first, last, index, active, model):
    while last - first > timedelta(seconds=60):
        middle = first + (last-first)/2
        if model(middle)[index] == active:
            first = middle
        else:
            last = middle
    return first + (last-first)/2


def event_ranges(start, end, model=geometry):
    grid = samples(start, end, 8)
    before = model(start)
    starts = [start if active else None for active in before]
    for first, last in zip(grid, grid[1:]):
        after = model(last)
        for index, (old, new) in enumerate(zip(before, after)):
            if old == new:
                continue
            boundary = refine(first, last, index, old, model)
            if new:
                starts[index] = boundary
            else:
                yield (index, starts[index], boundary, starts[index] == start, False)
                starts[index] = None
        before = after
    for index, first in enumerate(starts):
        if first is not None:
            yield index, first, end, first == start, True


def calculate(eph, ts, site, terrain, now):
    end = now + timedelta(days=3)
    observer = eph['earth'] + wgs84.latlon(site['lat'], site['lon'], elevation_m=site['elevation'])

    def jupiter(time):
        return observer.at(time).observe(eph['jupiter barycenter']).apparent()

    def observable(time):
        height, azimuth, _ = jupiter(time).altaz()
        sun = observer.at(time).observe(eph['sun']).apparent().altaz()[0].degrees
        return ((height.degrees >= 20) & (sun <= -12)
                & (height.degrees > combined_altitude(azimuth.degrees, site['horizon'], terrain)))

    observable.step_days = 5 / 1440
    local = list(intervals(ts, now, end, observable))
    rows = []
    for index, first, last, clipped_start, clipped_end in sorted(
            event_ranges(now, end), key=lambda row: row[1]):
        windows = []
        for a, b in local:
            start, stop = max(a, first), min(b, last)
            if stop - start < timedelta(minutes=5):
                continue
            times = samples(start, stop, 3)
            height = jupiter(ts.from_datetimes(times)).altaz()[0].degrees
            best = times[int(np.argmax(height))]
            windows.append({'start': iso(start), 'end': iso(stop),
                            **describe(jupiter(ts.from_datetime(best)), best)})
        rows.append({'moon': MOONS[index % 4], 'kind': KINDS[index // 4],
                     'start': iso(first), 'end': iso(last), 'ongoing': clipped_start,
                     'continues': clipped_end, 'windows': windows})
    return {'generated': iso(now), 'until': iso(end), 'events': rows}


def main():
    output = Path(sys.argv[1])
    fixture = sys.argv[2] == "fixture"
    try:
        site, terrain = point('active', fixture)
        now = utc(sys.argv[3]) if fixture and len(sys.argv) > 3 else (
            utc('2027-01-20T00:00:00Z') if fixture else datetime.now(UTC))
        ts = load.timescale(builtin=True)
        with closing(load_file(str(ROOT/'assets/de440s.bsp'))) as eph:
            result = calculate(eph, ts, site, terrain, now)
        write(output, result)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise SystemExit(f"Jupiter moon events unavailable: {exc}") from exc


if __name__ == "__main__":
    main()
