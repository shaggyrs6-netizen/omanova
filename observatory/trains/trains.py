"""Experimental local train geometry for individually tracked deployment members."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import re
import sys

import numpy as np
from skyfield.api import EarthSatellite, load, load_file, wgs84

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import DIRECTIONS, iso, station_rows, utc
from observatory.events.launches import BASE, normalise
from worker import DEFAULT_STATE, get_json, location, lock, read, settings_at, update_source, write

RECENT = BASE + "previous/?search=Starlink&limit=5&mode=detailed"
SUP = "https://celestrak.org/NORAD/elements/supplemental/"
GP = "https://celestrak.org/NORAD/elements/"
GROUP = re.compile(r"\bStarlink Group (\d{1,2}-\d{1,3})\b", re.I)
PREFIX = re.compile(r"(\d{4}-\d{3})[A-Z]+")
MEMBER = re.compile(r"STARLINK-\d+", re.I)
MAX_DEPLOYMENT_AGE = timedelta(days=14)
MAX_ELEMENT_AGE = timedelta(hours=36)
STEP = 10


def batch_for(launch):
    match = GROUP.search(launch["mission"] + " " + launch["name"])
    return match[1] if match and launch["provider"] == "SpaceX" else None


def designator(rows, batch, launched):
    if not isinstance(rows, list) or len(rows) > 100:
        raise ValueError("Unexpected supplemental response")
    prefixes = set()
    for row in rows:
        name = str(row.get("OBJECT_NAME", ""))
        match = PREFIX.fullmatch(str(row.get("OBJECT_ID", "")))
        if not match or not name.upper().startswith(f"STARLINK-G{batch} "):
            continue
        epoch = utc(row["EPOCH"])
        if match[1].startswith(str(launched.year)) and launched - timedelta(hours=2) <= epoch <= launched + timedelta(days=2):
            prefixes.add(match[1])
    if len(prefixes) != 1:
        raise ValueError("No unique launch-linked international designator")
    return prefixes.pop()


def individual_elements(rows, prefix, ts, now, launched):
    if not isinstance(rows, list) or len(rows) > 100:
        raise ValueError("Unexpected deployment response")
    matching = [row for row in rows if MEMBER.fullmatch(str(row.get("OBJECT_NAME", "")))
                and PREFIX.fullmatch(str(row.get("OBJECT_ID", "")))
                and row["OBJECT_ID"].startswith(prefix)
                and max(now - MAX_ELEMENT_AGE, launched) <= utc(row["EPOCH"]) <= now + timedelta(hours=2)]
    catalog = {row["NORAD_CAT_ID"]: row["OBJECT_NAME"] for row in matching}
    return station_rows(matching, ts, catalog=catalog, require_all=False)


def train_windows(eph, ts, site, elements, now):
    if len(elements) < 3:
        return []
    times = [now + timedelta(seconds=offset) for offset in range(0, 86400, STEP)]
    time = ts.from_datetimes(times)
    dark = (eph["earth"] + site).at(time).observe(eph["sun"]).apparent().altaz()[0].degrees <= -6
    indices = np.flatnonzero(dark)
    if not len(indices):
        return []
    time = time[indices]
    positions, masks = [], []
    for row in elements.values():
        satellite = EarthSatellite.from_omm(ts, row)
        age = np.abs(time.tt - satellite.epoch.tt) * 24
        altitude, azimuth, _ = (satellite - site).at(time).altaz()
        positions.append((altitude.degrees, azimuth.degrees))
        masks.append((altitude.degrees >= 15) & (age <= 36) & satellite.at(time).is_sunlit(eph))
    visibility = np.asarray(masks)
    qualifying = {}
    for index in np.flatnonzero(visibility.sum(axis=0) >= 3):
        members = np.flatnonzero(visibility[:, index])
        pairs = np.array([(positions[member][0][index], positions[member][1][index]) for member in members])
        altitude, azimuth = np.radians(pairs).T
        vectors = np.array([np.cos(altitude) * np.sin(azimuth), np.cos(altitude) * np.cos(azimuth),
                            np.sin(altitude)]).T
        # A six-degree radius around one member bounds the full spread to twelve.
        counts = (vectors @ vectors.T >= np.cos(np.radians(6))).sum(axis=1)
        best = int(np.argmax(counts))
        if counts[best] >= 3:
            el, az = pairs[best]
            qualifying[int(indices[index])] = {"time": iso(times[indices[index]]), "altitude": round(float(el)),
                "azimuth": round(float(az)) % 360, "direction": DIRECTIONS[int((az + 11.25) // 22.5) % 16],
                "count": int(counts[best])}

    runs = []
    for index, point in qualifying.items():
        if not runs or index != previous + 1:
            runs.append([])
        runs[-1].append(point)
        previous = index
    return [{"start": run[0], "end": run[-1],
             "best": max(run, key=lambda point: (point["count"], point["altitude"]))}
            for run in runs if len(run) >= 2]


def cached(state, key, url, validate, now, online):
    with lock(state):
        path = state / f"{key}.json"
        cache = read(path, {})
        before = cache.copy()
        if online:
            update_source(cache, now, timedelta(hours=2), lambda: get_json(url), validate,
                          stop_on_http=url.startswith((GP, SUP)))
        if cache != before:
            write(path, cache)
    if not cache.get("fetched") or now - utc(cache["fetched"]) > MAX_ELEMENT_AGE:
        return None
    return cache.get("data")


def recent_launches(data):
    rows = normalise(data)
    if not rows:
        raise ValueError("No recent launches returned")
    return rows


def live_rows(eph, ts, site, state, now, online):
    recent = cached(state, "recent", RECENT, recent_launches, now, online)
    output = []
    for launch in (normalise(recent) if recent else []):
        batch = batch_for(launch)
        launched = utc(launch["net"]) if launch["net"] else None
        if not batch or launch["statusId"] != 3 or not launched or not now - MAX_DEPLOYMENT_AGE <= launched < now:
            continue
        row = {"name": f"Starlink Group {batch}", "net": launch["net"], "source": launch["source"],
               "reason": "No usable launch-linked member elements.", "windows": [], "members": 0}
        try:
            group = cached(state, f"group-{batch}", SUP + f"sup-gp.php?FILE=starlink-g{batch}&FORMAT=JSON",
                           lambda rows: designator(rows, batch, launched), now, online)
            prefix = designator(group, batch, launched)
            row["orbitSource"] = SUP + f"table.php?FILE=starlink-g{batch}"
            data = cached(state, f"objects-{prefix}", GP + f"gp.php?INTDES={prefix}&FORMAT=JSON",
                          lambda rows: individual_elements(rows, prefix, ts, now, launched), now, online)
            elements = individual_elements(data, prefix, ts, now, launched)
        except (ValueError, KeyError, TypeError):
            elements = {}
        row["members"] = len(elements)
        if len(elements) >= 3:
            row["windows"] = train_windows(eph, ts, site, elements, now)
            row["reason"] = ("Several launch-matched members form a compact, sunlit group."
                             if row["windows"] else "Tracked members did not form a qualifying local group in the next 24 hours.")
        output.append(row)

    upcoming = read(ROOT / ".preview/plumes/schedule/live/launches.json", {})
    if not upcoming.get("launches"):
        upcoming = read(ROOT / ".preview/events/live/launches.json", {})
    for launch in upcoming.get("launches", []):
        batch = batch_for(launch)
        if batch and launch["net"] and utc(launch["net"]) >= now:
            output.append({"name": f"Starlink Group {batch}", "net": launch["net"], "source": launch["source"],
                           "reason": "Upcoming launch. Individual post-deployment elements are needed.",
                           "windows": [], "members": 0, "upcoming": True})
    return output, recent is not None


def prepare(output, state, fixture):
    if output.resolve().parent == DEFAULT_STATE.resolve() or state.resolve() == DEFAULT_STATE.resolve():
        raise ValueError("Train preview needs separate state")
    if fixture:
        now = utc("2026-11-09T13:00:00Z")
        site = wgs84.latlon(36.1627, -86.7816)
        online = False
    else:
        now = datetime.now(UTC)
        settings = settings_at(DEFAULT_STATE)
        place = location(settings)
        if not place:
            raise ValueError("Set an observing location in Omasky first.")
        site = wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])
        online = settings["online"]
    ts = load.timescale(builtin=True)
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        if fixture:
            # Use a known local pass with small synthetic along-track offsets.
            elements = read(ROOT / "observatory/satellites/fixture-elements.json", [])
            basis = next(row for row in elements if row["NORAD_CAT_ID"] == 25544)
            members = {index: {**basis, "NORAD_CAT_ID": index, "OBJECT_NAME": f"SIM-{index}",
                               "MEAN_ANOMALY": (basis["MEAN_ANOMALY"] + offset) % 360}
                       for index, offset in enumerate((-0.3, 0, 0.3, 0.6), 90001)}
            rows = [{"name": "Simulated deployment", "members": len(members), "reason": "Synthetic example, not an actual Starlink train.",
                     "windows": train_windows(eph, ts, site, members, now)}]
            recent_available = True
        else:
            rows, recent_available = live_rows(eph, ts, site, state, now, online)
    write(output, {"fixture": fixture, "online": online, "recentAvailable": recent_available,
                   "computed": iso(now), "batches": rows})


if __name__ == "__main__":
    try:
        output, state = map(Path, sys.argv[1:3])
        prepare(output, state, sys.argv[3] == "fixture")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Starlink trains: {exc}") from exc
