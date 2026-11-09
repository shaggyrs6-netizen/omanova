"""Local observing windows from a dated, geocentric JPL Horizons snapshot."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
import json
from pathlib import Path
import sys

import numpy as np
from skyfield import almanac
from skyfield.api import load, load_file, wgs84

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import DIRECTIONS, iso, utc
from observatory.moon.moon import intervals
from observatory.planets.planets import samples
from worker import DEFAULT_STATE, location, settings_at, write

CATALOG = Path(__file__).with_name("catalog.json")
MIN_WINDOW = timedelta(minutes=15)


def equipment(magnitude):
    # Comet light is spread across a coma. These are dark-sky planning tiers.
    if magnitude <= 4:
        return "eye"
    if magnitude <= 8:
        return "binoculars"
    if magnitude <= 12:
        return "telescope"
    return "large"


def interpolated_track(target, start_tt, step_days):
    coordinates = np.array(target["positions"]).T
    grid = start_tt + np.arange(coordinates.shape[1]) * step_days
    angles = np.radians(coordinates)
    angles[0] = np.unwrap(angles[0])
    angles[2] = np.unwrap(angles[2])

    def at(time):
        return [np.interp(time.tt, grid, values) for values in angles]

    return at


def horizontal(time, ra, dec, latitude, longitude):
    # Horizons apparent RA/Dec use the equator and equinox of date. Its
    # geocentric track is adequate for compass guidance on these distant comets.
    hour_angle = time.gast * np.pi / 12 + longitude - ra
    east = -np.cos(dec) * np.sin(hour_angle)
    north = np.sin(dec) * np.cos(latitude) - np.cos(dec) * np.cos(hour_angle) * np.sin(latitude)
    up = np.sin(dec) * np.sin(latitude) + np.cos(dec) * np.cos(hour_angle) * np.cos(latitude)
    return np.degrees(np.arctan2(up, np.hypot(east, north))), np.degrees(np.arctan2(east, north)) % 360


def calculate(eph, ts, site, now, catalog):
    start, end = utc(catalog["from"]), utc(catalog["until"])
    coverage = start <= now < end
    result = {"computed": iso(now), "until": iso(end), "available": coverage, "targets": []}
    if not coverage:
        return result

    observer = eph["earth"] + wgs84.latlon(site["lat"], site["lon"], elevation_m=site["elevation"])
    latitude, longitude = np.radians([site["lat"], site["lon"]])

    def dark(time):
        return observer.at(time).observe(eph["sun"]).apparent().altaz()[0].degrees <= -18

    dark.step_days = 1 / 48
    darkness = list(intervals(ts, now, end, dark))
    for target in catalog["targets"]:
        at = interpolated_track(target, ts.from_datetime(start).tt, catalog["stepSeconds"] / 86400)

        def position(time):
            _, _, ra, dec = at(time)
            return horizontal(time, ra, dec, latitude, longitude)

        def high(time):
            return position(time)[0] >= 20

        high.step_days = 1 / 96
        windows = []
        for dark_start, dark_end in darkness:
            for first, last in intervals(ts, dark_start, dark_end, high):
                if last - first < MIN_WINDOW:
                    continue
                times = samples(first + timedelta(minutes=2), last - timedelta(minutes=2), 4)
                time = ts.from_datetimes(times)
                altitude, bearing = position(time)
                moon_alt = observer.at(time).observe(eph["moon"]).apparent().altaz()[0].degrees
                moon_down = np.flatnonzero(moon_alt < -0.3)
                # Prefer a moon-free look when the comet is still well placed.
                comparable = moon_down[altitude[moon_down] >= altitude.max() - 8]
                best = int(comparable[np.argmax(altitude[comparable])] if comparable.size else np.argmax(altitude))
                look = times[best]
                ra, dec, _, _ = at(ts.from_datetime(look))
                az = float(bearing[best])
                windows.append({"start": iso(first), "end": iso(last), "time": iso(look),
                                "altitude": round(float(altitude[best])), "azimuth": round(az) % 360,
                                "direction": DIRECTIONS[int((az + 11.25) // 22.5) % 16],
                                "raHours": float(np.degrees(ra) % 360 / 15), "decDegrees": float(np.degrees(dec)),
                                "moonDown": bool(moon_alt[best] < -0.3),
                                "moonPercent": round(100 * float(almanac.fraction_illuminated(
                                    eph, "moon", ts.from_datetime(look))))})
        result["targets"].append({key: value for key, value in target.items() if key != "positions"}
                                 | {"equipment": equipment(target["magnitude"]), "windows": windows[:3]})
    return result


def prepare(output, fixture):
    if output.resolve().parent == DEFAULT_STATE.resolve():
        raise ValueError("Comet preview needs separate state")
    if fixture:
        site = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}
        now = utc("2026-11-09T12:00:00Z")
    else:
        site = location(settings_at(DEFAULT_STATE))
        now = datetime.now(UTC)
        if not site:
            raise ValueError("Set an observing location in OMANOVA first.")
    catalog = json.loads(CATALOG.read_text())
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        result = calculate(eph, load.timescale(builtin=True), site, now, catalog)
    write(output, {**result, "fixture": fixture})


if __name__ == "__main__":
    try:
        prepare(Path(sys.argv[1]), sys.argv[2] == "fixture")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Comet preview: {exc}") from exc
