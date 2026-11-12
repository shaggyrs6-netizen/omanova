"""Offline observing geometry for selected IMO visual meteor showers."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import sys
import json

import numpy as np
from skyfield import almanac
from skyfield.api import Star, load, load_file, wgs84

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import DIRECTIONS, iso, utc
from observatory.moon.moon import intervals
from worker import DEFAULT_STATE, location, settings_at, write

IMO = {
    2026: "https://www.imo.net/files/meteor-shower/cal2026.pdf",
    2027: "https://www.imo.net/files/data/calendar/cal2027.pdf",
}
# Peak radiant coordinates in degrees. Date-only entries use noon UTC solely
# to centre the search; the interface never presents that as a peak time.
CATALOG = json.loads(Path(__file__).with_name("showers.json").read_text())
SHOWERS = CATALOG["showers"]

SUN_LIMIT = -18
RADIANT_LIMIT = 20
MIN_WINDOW = timedelta(minutes=15)


def overlap(first, second):
    for a, b in first:
        for c, d in second:
            start, end = max(a, c), min(b, d)
            if end - start >= MIN_WINDOW:
                yield start, end


def calculate(eph, ts, place, now):
    observer = eph["earth"] + wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])

    def dark(t):
        return observer.at(t).observe(eph["sun"]).apparent().altaz()[0].degrees <= SUN_LIMIT

    def moon_down(t):
        return observer.at(t).observe(eph["moon"]).apparent().altaz()[0].degrees < -0.3

    dark.step_days = moon_down.step_days = 1 / 48
    results = []
    for shower in SHOWERS:
        name, published, ra, dec = (shower[key] for key in ("name", "peak", "ra", "dec"))
        if now >= utc(shower["activeEnd"] + "T00:00:00Z") + timedelta(days=1):
            continue
        date_only = len(published) == 10
        peak = utc(published + "T12:00:00Z" if date_only else published)
        start, end = max(now, peak - timedelta(hours=24)), peak + timedelta(hours=24)
        # Keep still-active showers listed after the peak; precise viewing
        # directions use the published peak radiant only near the peak.
        past_peak = end - start < MIN_WINDOW
        radiant = Star(ra_hours=ra / 15, dec_degrees=dec)

        def position(t):
            return observer.at(t).observe(radiant).apparent().altaz()

        def high(t):
            return position(t)[0].degrees >= RADIANT_LIMIT

        high.step_days = 1 / 48
        darkness = [] if past_peak else list(intervals(ts, start, end, dark))
        moonless = [] if past_peak else list(intervals(ts, start, end, moon_down))
        windows = []
        for first, last in overlap([] if past_peak else intervals(ts, start, end, high), darkness):
            span = (last - first).total_seconds()
            samples = [first + timedelta(seconds=float(offset))
                       for offset in np.linspace(0, span, int(np.ceil(span / 300)) + 1)]
            altitude, azimuth, _ = position(ts.from_datetimes(samples))
            top = int(np.argmax(altitude.degrees))
            bearing = azimuth.degrees[top]
            best = samples[top]
            lit = float(almanac.fraction_illuminated(eph, "moon", ts.from_datetime(best)))
            windows.append({
                "start": iso(first), "end": iso(last), "highest": iso(best),
                "altitude": round(float(altitude.degrees[top])),
                "direction": DIRECTIONS[int((bearing + 11.25) // 22.5) % 16],
                "illumination": round(lit * 100),
                "moonDown": bool(moon_down(ts.from_datetime(best))),
                "moonless": [{"start": iso(a), "end": iso(b)}
                             for a, b in overlap([(first, last)], moonless)],
            })
        results.append({"name": name, "peak": published, "dateOnly": date_only,
                        "source": IMO[peak.year], "windows": windows,
                        "activeStart": shower["activeStart"], "activeEnd": shower["activeEnd"],
                        "activeNow": utc(shower["activeStart"] + "T00:00:00Z") <= now < utc(shower["activeEnd"] + "T00:00:00Z") + timedelta(days=1),
                        "peakPassed": past_peak})
    return results


def prepare(output, mode):
    if output.resolve().parent == DEFAULT_STATE.resolve():
        raise ValueError("Meteor preview needs separate state")
    fixture = mode == "fixture"
    if fixture:
        place = {"lat": 36.1627, "lon": -86.7816, "elevation": 0}
        now = utc("2026-11-09T12:00:00Z")
    else:
        place = location(settings_at(DEFAULT_STATE))
        now = datetime.now(UTC)
        if not place:
            raise ValueError("Set an observing location in OMANOVA first.")
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        showers = calculate(eph, load.timescale(builtin=True), place, now)
    write(output, {"showers": showers, "fixture": fixture, "until": CATALOG["until"], "expired": now >= utc(CATALOG["until"])})


if __name__ == "__main__":
    try:
        prepare(Path(sys.argv[1]), sys.argv[2])
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Meteor preview: {exc}") from exc
