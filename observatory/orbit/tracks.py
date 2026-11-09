"""Offline ground tracks and observer geometry for the separate Orbit preview."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import os
import sys

import numpy as np
from skyfield.api import EarthSatellite, load, load_file, wgs84

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from astronomy import STATIONS, iso, predict, station_rows, utc
from worker import DEFAULT_STATE, DEMO_NOW, ROOT, location, read, settings_at, write


def ground_distance(lat, lon, site_lat, site_lon):
    """Spherical surface distance to the sub-satellite point, in kilometres."""
    lat, lon, site_lat, site_lon = np.deg2rad([lat, lon, site_lat, site_lon])
    h = np.sin((lat - site_lat) / 2) ** 2 + np.cos(lat) * np.cos(site_lat) * np.sin((lon - site_lon) / 2) ** 2
    return 6371.0088 * 2 * np.arcsin(np.sqrt(np.clip(h, 0, 1)))


def samples(satellite, site, ts, start, end, step, relative=False, landmarks=()):
    span = (end - start).total_seconds()
    dates = sorted(set([start + timedelta(seconds=offset) for offset in range(0, int(span), step)]
                       + [end, *landmarks]))
    time = ts.from_datetimes(dates)
    position = satellite.at(time)
    lat, lon = wgs84.latlon_of(position)
    if not relative:
        return [[round(float(x), 4), round(float(y), 4)] for x, y in zip(lon.degrees, lat.degrees)]
    altitude = wgs84.height_of(position).km
    elevation, azimuth, distance = (satellite - site).at(time).altaz()
    surface = [ground_distance(y, x, site.latitude.degrees, site.longitude.degrees)
               for y, x in zip(lat.degrees, lon.degrees)]
    return [
        {"time": iso(stamp), "lat": round(float(y), 4), "lon": round(float(x), 4),
         "altitude": round(float(height)), "ground": round(float(arc)), "slant": round(float(slant)),
         "az": round(float(bearing), 1) % 360, "el": round(float(elev), 1)}
        for stamp, y, x, height, arc, slant, bearing, elev in
        zip(dates, lat.degrees, lon.degrees, altitude, surface, distance.km, azimuth.degrees, elevation.degrees)
    ]


def build(rows, place, now, eph, ts):
    by_station = station_rows(rows, ts)
    predictions = predict(rows, ts, eph, place, now)
    site = wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])
    stations = []
    for number, name in STATIONS.items():
        satellite = EarthSatellite.from_omm(ts, by_station[number])
        events = [event for event in predictions if event["source_id"] == number]
        upcoming = events[:4]
        visible = next((event for event in events if event["windows"] and event["confidence"] != "Stale orbit"), None)
        if visible and visible not in upcoming:
            upcoming = [*upcoming, visible]
        passes = []
        for event in upcoming:
            rise, peak, setting = (utc(event[key]) for key in ("start", "peak", "end"))
            period = timedelta(days=1 / float(by_station[number]["MEAN_MOTION"]))
            windows = [{"start": w["start"]["time"], "end": w["end"]["time"]} for w in event["windows"]]
            landmarks = [peak, *(utc(w[key]) for w in windows for key in ("start", "end"))]
            passes.append({
                "id": event["id"], "rise": event["start"], "peak": event["peak"], "set": event["end"],
                "reason": event["reason"], "confidence": event["confidence"], "windows": windows,
                "track": samples(satellite, site, ts, peak - period / 2, peak + period / 2, 25),
                "pass": samples(satellite, site, ts, rise, setting, 5, relative=True, landmarks=landmarks),
            })
        stations.append({"name": name, "epoch": iso(utc(by_station[number]["EPOCH"])), "passes": passes,
                         "preferred": visible["id"] if visible else (passes[0]["id"] if passes else "")})
    return stations


def prepare(output, fixture):
    os.umask(0o077)
    if output.resolve().parent == DEFAULT_STATE.resolve():
        raise ValueError("Orbit preview needs separate state")
    if fixture:
        now = DEMO_NOW
        place = {"id": "nashville", "name": "Nashville fixture", "lat": 36.1627, "lon": -86.7816, "elevation": 0}
        rows = read(ROOT / "tests/fixtures/stations.json", [])
    else:
        now = datetime.now(UTC)
        place = location(settings_at(DEFAULT_STATE))
        rows = read(DEFAULT_STATE / "orbit.json", {}).get("data", [])
        if not place or not rows:
            raise ValueError("Set an observing location and download orbital elements in OMANOVA first.")
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        stations = build(rows, place, now, eph, load.timescale(builtin=True))
    write(output, {"fixture": fixture, "generated": iso(now),
                   "observer": {"lat": place["lat"], "lon": place["lon"]}, "stations": stations})


if __name__ == "__main__":
    try:
        prepare(Path(sys.argv[1]), sys.argv[2] == "fixture")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Orbit preview: {exc}") from exc
