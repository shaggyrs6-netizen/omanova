"""NOAA SWPC aurora context and local horizon screening."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import sys

import numpy as np
from skyfield.api import load, load_file, wgs84

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import DIRECTIONS, iso, utc
from observatory.moon.moon import intervals
from worker import DEFAULT_STATE, get_json, location, lock, read, settings_at, update_source, write

NOAA = "https://services.swpc.noaa.gov/"
OVATION = NOAA + "json/ovation_aurora_latest.json"
KP = NOAA + "products/noaa-planetary-k-index-forecast.json"
DARK_SUN = -12


def oval_data(data):
    cells = np.asarray(data["coordinates"], dtype=float)
    if (cells.ndim != 2 or cells.shape[1] != 3 or not 3 <= len(cells) <= 70000
            or not np.isfinite(cells).all() or (np.abs(cells[:, 1]) > 90).any()
            or (cells[:, 2] < 0).any() or (cells[:, 2] > 100).any()):
        raise ValueError("Unexpected OVATION grid")
    return utc(data["Observation Time"]), utc(data["Forecast Time"]), cells


def kp_blocks(data):
    if not isinstance(data, list) or not data or len(data) > 300:
        raise ValueError("Unexpected Kp forecast")
    if isinstance(data[0], list):
        keys, *rows = data
        data = [dict(zip(keys, row)) for row in rows]
    blocks = {}
    for row in data:
        if not isinstance(row, dict) or row.get("observed") not in ("predicted", "estimated"):
            continue
        start, value = utc(row["time_tag"]), float(row["kp"])
        if not 0 <= value <= 9:
            raise ValueError("Kp outside expected range")
        blocks[start] = value
    if not blocks:
        raise ValueError("No predicted Kp blocks")
    return sorted(blocks.items())


def sightline(site, t, cells):
    # OVATION scores model activity in the oval. They are not a local
    # viewing probability, so use them only to screen the sightline.
    selected = cells[(cells[:, 2] >= 10) & (np.abs(cells[:, 1] - site.latitude.degrees) <= 19)]
    if not len(selected):
        return None
    lon, lat, score = selected.T
    targets = wgs84.latlon(lat, (lon + 180) % 360 - 180, elevation_m=110000)
    altitude, bearing, _ = (targets - site).at(t.ts.tt_jd(np.full(len(lat), t.tt))).altaz()
    el, az = altitude.degrees, bearing.degrees
    # Require multiple model cells above a clear horizon rather than one pixel.
    candidates = np.flatnonzero(el >= 3)
    if len(candidates) < 3:
        return None
    top = max(candidates, key=lambda i: (score[i], el[i]))
    degrees = float(az[top])
    return {"direction": DIRECTIONS[int((degrees + 11.25) // 22.5) % 16],
            "bearing": round(degrees) % 360, "elevation": round(float(el[top]))}


def calculate(eph, ts, place, now, oval, forecast):
    site = wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])
    observer = eph["earth"] + site

    def sun_altitude(t):
        return observer.at(t).observe(eph["sun"]).apparent().altaz()[0].degrees

    def dark(t):
        return sun_altitude(t) <= DARK_SUN

    dark.step_days = 1 / 48
    nights = []
    for first, last in intervals(ts, now, now + timedelta(days=3), dark):
        windows = [(value, max(start, first), min(start + timedelta(hours=3), last))
                   for start, value in forecast if start < last and start + timedelta(hours=3) > first]
        strongest = max(windows, default=None, key=lambda row: row[0])
        nights.append({"start": iso(first), "end": iso(last),
                       "kp": strongest[0] if strongest else None,
                       "kpStart": iso(strongest[1]) if strongest else None,
                       "kpEnd": iso(strongest[2]) if strongest else None})

    current = {"verdict": "uncertain"}
    if oval:
        observed, valid, cells = oval
        current.update(observed=iso(observed), valid=iso(valid))
        # Never use fetch time to disguise an old or expired model run.
        if (timedelta(0) <= now - observed <= timedelta(minutes=100)
                and now <= valid + timedelta(minutes=10)
                and observed <= valid <= now + timedelta(minutes=100)):
            t = ts.from_datetime(valid)
            sun = float(sun_altitude(t))
            look = sightline(site, t, cells)
            current.update(sun=round(sun, 1), look=look,
                           verdict="daylight" if sun > DARK_SUN else "possible" if look else "unlikely")
    return {"current": current, "nights": nights[:3]}


def cache_read(state, key, url, validator, now, period, max_bytes):
    with lock(state):
        path = state / f"{key}.json"
        cache = read(path, {})
        before = cache.copy()
        update_source(cache, now, period, lambda: get_json(url, max_bytes=max_bytes), validator)
        if cache != before:
            write(path, cache)
    return cache


def prepare(output, state, fixture):
    if output.resolve().parent == DEFAULT_STATE.resolve() or state.resolve() == DEFAULT_STATE.resolve():
        raise ValueError("Aurora preview needs separate state")
    if fixture:
        place = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}
        now = utc("2026-11-10T02:00:00Z")
        valid = now + timedelta(minutes=35)
        oval = now - timedelta(minutes=5), valid, np.array([[lon, lat, 40]
                for lat in range(40, 45) for lon in range(-89, -84)])
        forecast = [(now + timedelta(hours=3 * index), value)
                    for index, value in enumerate((7, 5, 2, 2))]
        issues = []
    else:
        now = datetime.now(UTC)
        place = location(settings_at(DEFAULT_STATE))
        if not place:
            raise ValueError("Set an observing location in OMANOVA first.")
        oval_cache = cache_read(state, "oval", OVATION, oval_data, now, timedelta(minutes=5), 1400000)
        kp_cache = cache_read(state, "kp", KP, kp_blocks, now, timedelta(minutes=20), 65536)
        oval = oval_data(oval_cache["data"]) if "data" in oval_cache else None
        kp_fresh = kp_cache.get("fetched") and now - utc(kp_cache["fetched"]) <= timedelta(hours=12)
        forecast = kp_blocks(kp_cache["data"]) if kp_fresh and "data" in kp_cache else []
        issues = [name for name, cache in (("OVATION", oval_cache), ("Kp", kp_cache)) if cache.get("error")]
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        result = calculate(eph, load.timescale(builtin=True), place, now, oval, forecast)
    write(output, {**result, "fixture": fixture, "computed": iso(now), "issues": issues})


if __name__ == "__main__":
    try:
        output, state = map(Path, sys.argv[1:3])
        prepare(output, state, sys.argv[3] == "fixture")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Aurora preview: {exc}") from exc
