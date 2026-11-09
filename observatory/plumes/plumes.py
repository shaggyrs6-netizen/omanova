"""Screen timed plume-producing ascent points against local viewing geometry."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from math import isfinite
from pathlib import Path
import sys

from skyfield.api import load, load_file, wgs84

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import iso, utc
from observatory.events.launches import prepare as prepare_schedule, stream_url
from observatory.planets.planets import describe
from worker import DEFAULT_STATE, DEMO_NOW, location, read, settings_at, write

DARK_SUN = -6
MIN_ALTITUDE = 5
MAX_SAMPLE_GAP = 20
MAX_SCHEDULE_AGE = timedelta(hours=2)
FIXTURE_ID = "421785e3-d1b4-4874-ae34-344a24fa2a01"
TRACK_DIR = Path(__file__).resolve().parent


def validate_points(raw):
    if not isinstance(raw, list) or not 2 <= len(raw) <= 300:
        raise ValueError("Track sample count out of range")
    points = []
    for point in raw:
        if not isinstance(point, list) or len(point) != 4 or not all(
                type(value) in (int, float) and isfinite(value) for value in point):
            raise ValueError("Track needs numeric elapsed seconds, latitude, longitude and altitude")
        seconds, lat, lon, km = point
        if not (0 <= seconds <= 1800 and -90 <= lat <= 90 and -180 <= lon <= 180 and 0 <= km <= 1500):
            raise ValueError("Track sample out of range")
        if points and seconds <= points[-1][0]:
            raise ValueError("Track samples must be in time order")
        points.append((seconds, lat, lon, km))
    return points


def windows_for_track(eph, ts, site, net, points):
    observer = eph["earth"] + site
    runs = []
    run = []
    previous = None
    for seconds, lat, lon, height in points:
        instant = net + timedelta(seconds=seconds)
        t = ts.from_datetime(instant)
        target = wgs84.latlon(lat, lon, elevation_m=height * 1000)
        local = (target - site).at(t)
        sun_alt = observer.at(t).observe(eph["sun"]).apparent().altaz()[0].degrees
        usable = (sun_alt <= DARK_SUN and local.altaz()[0].degrees >= MIN_ALTITUDE
                  and target.at(t).is_sunlit(eph))
        if run and (seconds - previous > MAX_SAMPLE_GAP or not usable):
            runs.append(run)
            run = []
        if usable:
            run.append(describe(local, instant))
        previous = seconds
    if run:
        runs.append(run)
    return [{"start": row[0], "end": row[-1], "highest": max(row, key=lambda item: item["altitude"])}
            for row in runs if len(row) >= 2]


def evaluate(eph, ts, site, row, track, now, schedule_fresh, fixture):
    result = {**row, "verdict": "unconfirmed", "reason": "", "windows": []}
    raw_net = row.get("net")
    net = utc(raw_net) if raw_net else None
    if not schedule_fresh:
        return {**result, "reason": "Launch schedule is stale or unavailable."}
    if not net or net <= now or row.get("precision") not in ("SEC", "MIN") or row.get("statusId") != 1:
        return {**result, "reason": "A current, minute-level go-for-launch time is needed."}
    sun_alt = (eph["earth"] + site).at(ts.from_datetime(net)).observe(eph["sun"]).apparent().altaz()[0].degrees
    result["sunAltitude"] = round(float(sun_alt), 1)
    if not isinstance(track, dict) or not track:
        return {**result, "reason": "No sourced, timed plume-producing ascent track is available."}
    source = stream_url(track.get("source"))
    if track.get("net") != raw_net or (not fixture and not source):
        return {**result, "reason": "Track provenance or launch time does not match this schedule."}
    try:
        points = validate_points(track.get("points"))
    except ValueError:
        return {**result, "reason": "Track samples are incomplete or invalid."}
    windows = windows_for_track(eph, ts, site, net, points)
    return {**result, "verdict": "possible" if windows else "unconfirmed", "windows": windows,
            "trackSource": source,
            "reason": ("Sampled exhaust positions are sunlit, above the local horizon and against a dark sky."
                       if windows else "The supplied samples do not establish a usable local window.")}


def prepare(output, schedule_path, fixture):
    if output.resolve().parent == DEFAULT_STATE.resolve():
        raise ValueError("Plume preview needs separate state")
    now = DEMO_NOW if fixture else datetime.now(UTC)
    if fixture:
        place = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}
        tracks = read(TRACK_DIR / "fixture-track.json", {})
    else:
        place = location(settings_at(DEFAULT_STATE))
        if not place:
            raise ValueError("Set an observing location in OMANOVA first.")
        tracks = read(TRACK_DIR / "verified-tracks.json", {})
    if not isinstance(tracks, dict):
        tracks = {}
    schedule = read(schedule_path, {})
    fetched = schedule.get("fetched")
    fresh = bool(fetched and timedelta(0) <= now - utc(fetched) <= MAX_SCHEDULE_AGE
                 and not schedule.get("error"))
    launches = schedule.get("launches", [])
    if fixture:
        # This nearby example is explicitly fictional and separate from real missions.
        launches = [{**row, "name": "Simulated twilight ascent", "provider": "Synthetic fixture",
                     "site": "Sample ascent over the southeastern US", "region": "",
                     "net": tracks[FIXTURE_ID]["net"], "windowStart": None, "windowEnd": None,
                     "source": None, "stream": None}
                    if row["id"] == FIXTURE_ID else {**row, "source": None, "stream": None}
                    for row in launches]
    site = wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        ts = load.timescale(builtin=True)
        rows = [evaluate(eph, ts, site, row, tracks.get(row["id"]), now, fresh, fixture) for row in launches]
    rows.sort(key=lambda row: row["verdict"] != "possible")
    write(output, {"fixture": fixture, "fetched": fetched, "error": schedule.get("error"),
                   "fresh": fresh, "launches": rows})


if __name__ == "__main__":
    try:
        output, state = map(Path, sys.argv[1:3])
        fixture = sys.argv[3] == "fixture"
        prepare_schedule(state, fixture)
        prepare(output, state / "launches.json", fixture)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Plume preview: {exc}") from exc
