"""Offline planet viewing windows and close approaches using the local JPL kernel."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from itertools import combinations
from pathlib import Path
import sys

import numpy as np
from skyfield.api import load, load_file, wgs84

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import DIRECTIONS, iso, utc
from observatory.moon.moon import intervals
from worker import DEFAULT_STATE, location, settings_at, write

PLANETS = ("Mercury", "Venus", "Mars", "Jupiter", "Saturn")
SUN_LIMIT = -6
ALTITUDE_LIMIT = 10
MIN_WINDOW = timedelta(minutes=10)


def samples(start, end, minutes):
    count = int(np.ceil((end - start).total_seconds() / (60 * minutes)))
    return [start + (end - start) * (index / count) for index in range(count + 1)]


def describe(position, time):
    altitude, bearing, _ = position.altaz()
    azimuth = float(bearing.degrees)
    return {"time": iso(time), "altitude": round(float(altitude.degrees)),
            "azimuth": round(azimuth) % 360,
            "direction": DIRECTIONS[int((azimuth + 11.25) // 22.5) % 16]}


def calculate(eph, ts, place, now):
    earth = eph["earth"]
    site = earth + wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])
    bodies = {name: eph[name.lower() + (" barycenter" if name in PLANETS[2:] else "")]
              for name in (*PLANETS, "Moon", "Sun")}

    def apparent(name, time, origin=site):
        return origin.at(time).observe(bodies[name]).apparent()

    def sun_altitude(time):
        return apparent("Sun", time).altaz()[0].degrees

    def visible_windows(names, start, end, limit=None):
        def visible(time):
            positions = [apparent(name, time) for name in names]
            valid = sun_altitude(time) <= SUN_LIMIT
            for position in positions:
                valid = valid & (position.altaz()[0].degrees >= ALTITUDE_LIMIT)
            if limit is not None:
                valid = valid & (positions[0].separation_from(positions[1]).degrees <= limit)
            return valid

        visible.step_days = 5 / 1440
        return [(first, last) for first, last in intervals(ts, start, end, visible)
                if last - first >= MIN_WINDOW]

    highlights = []
    for name in PLANETS:
        windows = []
        for first, last in visible_windows((name,), now, now + timedelta(days=1)):
            times = samples(first, last, 3)
            altitudes = apparent(name, ts.from_datetimes(times)).altaz()[0].degrees
            best = times[int(np.argmax(altitudes))]
            windows.append({"start": iso(first), "end": iso(last),
                            **describe(apparent(name, ts.from_datetime(best)), best)})
        highlights.append({"name": name, "windows": windows})

    # Find one event around each Earth-centred minimum. Using the same origin
    # throughout the scan avoids duplicate lunar minima from daily parallax.
    end = now + timedelta(days=30)
    grid = samples(now - timedelta(hours=1), end + timedelta(hours=1), 30)
    time = ts.from_datetimes(grid)
    positions = {name: apparent(name, time, earth) for name in (*PLANETS, "Moon")}
    pairings = []
    for first, second in combinations(positions, 2):
        limit = 8 if second == "Moon" else 5
        separation = positions[first].separation_from(positions[second]).degrees
        candidates = np.flatnonzero((separation[1:-1] < separation[:-2])
                                    & (separation[1:-1] <= separation[2:])) + 1
        for index in candidates:
            if separation[index] > limit + 0.1:
                continue
            fine = samples(grid[index - 1], grid[index + 1], 1)
            time = ts.from_datetimes(fine)
            angles = apparent(first, time, earth).separation_from(apparent(second, time, earth)).degrees
            best = int(np.argmin(angles))
            peak = fine[best]
            if not now <= peak <= end or angles[best] > limit:
                continue
            start = max(now, peak - timedelta(hours=36))
            stop = peak + timedelta(hours=36)
            windows = []
            for rise, setting in visible_windows((first, second), start, stop, limit):
                # Keep the suggested time inside the window when rounding to minutes.
                times = samples(rise + timedelta(minutes=2), setting - timedelta(minutes=2), 3)
                time = ts.from_datetimes(times)
                local = apparent(first, time).separation_from(apparent(second, time)).degrees
                first_altitude = apparent(first, time).altaz()[0].degrees
                second_altitude = apparent(second, time).altaz()[0].degrees
                height = np.minimum(first_altitude, second_altitude)
                # A slightly wider pairing high in the sky is easier to spot.
                near = np.flatnonzero(local <= local.min() + 0.15)
                pick = near[int(np.argmax(height[near]))]
                look = times[pick]
                look_time = ts.from_datetime(look)
                windows.append({"start": iso(rise), "end": iso(setting), "time": iso(look),
                                "separation": float(local[pick]),
                                "positions": [{"name": name, **describe(apparent(name, look_time), look)}
                                              for name in (first, second)]})
            # Prefer the usable window with the tightest suggested pairing.
            window = min(windows, key=lambda item: item["separation"], default=None)
            pairings.append({"name": f"{first} and {second}", "peak": iso(peak),
                             "separation": float(angles[best]), "window": window})
    return {"computed": iso(now), "highlights": highlights,
            "pairings": sorted(pairings, key=lambda item: item["peak"])}


def prepare(output, fixture):
    if output.resolve().parent == DEFAULT_STATE.resolve():
        raise ValueError("Planet preview needs separate state")
    if fixture:
        place = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}
        now = utc("2026-11-09T12:00:00Z")
    else:
        place = location(settings_at(DEFAULT_STATE))
        now = datetime.now(UTC)
        if not place:
            raise ValueError("Set an observing location in Omasky first.")
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        data = calculate(eph, load.timescale(builtin=True), place, now)
    write(output, {**data, "fixture": fixture})


if __name__ == "__main__":
    try:
        prepare(Path(sys.argv[1]), sys.argv[2] == "fixture")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Planet preview: {exc}") from exc
