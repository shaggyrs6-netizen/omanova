"""Offline lunar phases and local observing windows for the Moon preview."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import os
import sys

import numpy as np
from skyfield import almanac
from skyfield.api import load, load_file, wgs84

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import DIRECTIONS, iso, utc
from worker import DEFAULT_STATE, location, settings_at, write

DARK_SUN = -6
MIN_MOON = 5
MONTH_NAMES = (
    "Wolf Moon", "Snow Moon", "Worm Moon", "Pink Moon", "Flower Moon",
    "Strawberry Moon", "Buck Moon", "Sturgeon Moon", "Corn Moon",
    "Full Moon", "Beaver Moon", "Cold Moon",
)


def full_moon_details(eph, ts, full):
    """Use common North American names and the desktop's calendar month."""
    start = ts.from_datetime(full - timedelta(days=65))
    end = ts.from_datetime(full + timedelta(days=65))
    times, phases = almanac.find_discrete(start, end, almanac.moon_phases(eph))
    fulls = times[phases == 2].utc_datetime()
    index = min(range(len(fulls)), key=lambda i: abs(fulls[i] - full))
    previous = fulls[index - 1]
    local, prior_local = full.astimezone(), previous.astimezone()
    name = MONTH_NAMES[local.month - 1]
    if (local.year, local.month) == (prior_local.year, prior_local.month):
        name = "Blue Moon"
    equinoxes, seasons = almanac.find_discrete(start, end, almanac.seasons(eph))
    for equinox in equinoxes[seasons == 2].utc_datetime():
        harvest = min(fulls, key=lambda instant: abs(instant - equinox))
        if harvest == fulls[index]:
            name = "Harvest Moon"
        elif harvest == previous:
            name = "Hunter’s Moon"

    orbit = eph["moon"] - eph["earth"]

    def receding(t):
        state = orbit.at(t)
        return np.sum(state.position.km * state.velocity.km_per_s, axis=0) > 0

    receding.step_days = 0.5
    instant = ts.from_datetime(full)
    extrema, _ = almanac.find_discrete(start, end, receding)
    before = extrema[extrema.tt < instant.tt][-1]
    after = extrema[extrema.tt >= instant.tt][0]
    near, far = sorted(orbit.at(t).distance().km for t in (before, after))
    distance = orbit.at(instant).distance().km
    fraction = (distance - near) / (far - near)
    size = "Supermoon" if fraction <= 0.1 else "Micromoon" if fraction >= 0.9 else "Neither supermoon nor micromoon"
    return {"name": name, "size": size, "distanceKm": round(distance)}


def phase_name(angle):
    if min(angle, 360 - angle) < 1:
        return "New Moon"
    for degrees, name in ((90, "First Quarter"), (180, "Full Moon"), (270, "Last Quarter")):
        if abs(angle - degrees) < 1:
            return name
    return ("Waxing crescent", "Waxing gibbous", "Waning gibbous", "Waning crescent")[int(angle // 90)]


def intervals(ts, start, end, condition):
    beginning = start if condition(ts.from_datetime(start)) else None
    times, states = almanac.find_discrete(ts.from_datetime(start), ts.from_datetime(end), condition)
    for time, state in zip(times.utc_datetime(), states):
        if state:
            beginning = time
        elif beginning is not None:
            if time > beginning:
                yield beginning, time
            beginning = None
    if beginning is not None and end > beginning:
        yield beginning, end


def calculate(eph, ts, place, now):
    site = wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])
    observer = eph["earth"] + site
    moon, sun = eph["moon"], eph["sun"]
    t = ts.from_datetime(now)

    def moon_position(time):
        return observer.at(time).observe(moon).apparent().altaz()

    def sun_position(time):
        return observer.at(time).observe(sun).apparent().altaz()[0].degrees

    def above_five(time):
        return moon_position(time)[0].degrees >= MIN_MOON

    def dark_enough(time):
        return sun_position(time) <= DARK_SUN

    # Solve each crossing separately, so a brief overlap of the two ranges
    # is retained even if no coarse sample falls inside the overlap.
    above_five.step_days = dark_enough.step_days = 0.025

    def describe(time):
        altitude, bearing, _ = moon_position(ts.from_datetime(time))
        az = round(float(bearing.degrees), 1) % 360
        return {"time": iso(time), "az": az, "el": round(float(altitude.degrees), 1),
                "direction": DIRECTIONS[int((az + 11.25) // 22.5) % 16]}

    def windows(start, end):
        moon_up = list(intervals(ts, start, end, above_five))
        dark = list(intervals(ts, start, end, dark_enough))
        result = []
        for moon_start, moon_end in moon_up:
            for dark_start, dark_end in dark:
                first, last = max(moon_start, dark_start), min(moon_end, dark_end)
                span = (last - first).total_seconds()
                if span < 60:
                    continue
                sample = [first + timedelta(seconds=float(offset))
                          for offset in np.linspace(0, span, max(2, int(np.ceil(span / 240)) + 1))]
                altitude = moon_position(ts.from_datetimes(sample))[0].degrees
                peak = sample[int(np.argmax(altitude))]
                result.append({"start": describe(first), "peak": describe(peak), "end": describe(last),
                               "illumination": float(almanac.fraction_illuminated(eph, "moon", ts.from_datetime(peak)))})
        return result

    phase_times, phases = almanac.find_discrete(
        t, ts.from_datetime(now + timedelta(days=38)), almanac.moon_phases(eph))
    phase_events = [{"name": almanac.MOON_PHASES[int(phase)], "time": iso(instant)}
                    for instant, phase in zip(phase_times.utc_datetime(), phases)]
    full = next(instant for instant, phase in zip(phase_times.utc_datetime(), phases) if phase == 2)
    near_start, near_end = full - timedelta(hours=36), full + timedelta(hours=36)
    # Search beyond the displayed range so the first and last evening keep
    # their actual crossings instead of inheriting the search boundaries.
    full_windows = [item for item in windows(max(now, near_start - timedelta(days=1)), near_end + timedelta(days=1))
                    if utc(item["end"]["time"]) >= near_start and utc(item["start"]["time"]) <= near_end]
    full_windows = sorted(full_windows, key=lambda item: max(
        (utc(item["start"]["time"]) - full).total_seconds(),
        (full - utc(item["end"]["time"])).total_seconds(), 0,
    ))[:3]
    horizon = almanac.risings_and_settings(eph, moon, site, radius_degrees=0.25)
    crosses, states = almanac.find_discrete(t, ts.from_datetime(now + timedelta(days=4)), horizon)
    horizon_events = {label: next((describe(stamp) for stamp, state in zip(crosses.utc_datetime(), states)
                                   if state == rising), None)
                      for label, rising in (("rise", True), ("set", False))}
    angle = float(almanac.moon_phase(eph, t).degrees)
    lit = float(almanac.fraction_illuminated(eph, "moon", t))
    full_sun = float(sun_position(ts.from_datetime(full)))
    return {"computed": iso(now), "phase": phase_name(angle), "waxing": angle < 180,
            "illumination": lit, "position": describe(now), "horizon": horizon_events,
            "nextWindows": windows(now, now + timedelta(days=4))[:2],
            "phases": phase_events[:4],
            "full": {**describe(full), "dark": full_sun <= DARK_SUN,
                     "windows": sorted(full_windows, key=lambda item: item["start"]["time"])}}


def prepare(output, fixture):
    os.umask(0o077)
    if output.resolve().parent == DEFAULT_STATE.resolve():
        raise ValueError("Moon preview needs separate state")
    if fixture:
        place = {"name": "Nashville fixture", "lat": 36.1627, "lon": -86.7816, "elevation": 0}
        now = utc("2026-11-09T12:00:00Z")
    else:
        place = location(settings_at(DEFAULT_STATE))
        now = datetime.now(UTC)
        if not place:
            raise ValueError("Set an observing location in Omasky first.")
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        ts = load.timescale(builtin=True)
        result = calculate(eph, ts, place, now)
        if os.environ.get("OMASKY_NAMED_MOONS") == "1":
            full = result["full"]
            full.update(full_moon_details(eph, ts, utc(full["time"])))
    write(output, {**result, "fixture": fixture})


if __name__ == "__main__":
    try:
        prepare(Path(sys.argv[1]), sys.argv[2] == "fixture")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Moon preview: {exc}") from exc
