"""Solar disk overlap and lunar shadow contacts from the local JPL kernel."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import sys

import numpy as np
from skyfield import almanac, eclipselib
from skyfield.api import load, load_file, wgs84
from skyfield.constants import ERAD
from skyfield.functions import angle_between

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import iso, utc
from observatory.moon.moon import intervals
from observatory.planets.planets import describe, samples
from worker import DEFAULT_STATE, location, settings_at, write

END = utc("2030-01-01T00:00:00Z")
SUN_RADIUS = 696340.0
MOON_RADIUS = 1737.1
SEARCH_STEP = 1 / 1440


def crossings(ts, start, end, margin):
    def inside(t):
        return margin(t) >= 0

    inside.step_days = SEARCH_STEP
    return list(intervals(ts, start, end, inside))


def clip_to_horizon(ts, spans, altitude, threshold, now):
    visible = []
    for start, end in spans:
        start = max(start, now)
        if end > start:
            visible.extend(crossings(ts, start, end, lambda t: altitude(t) - threshold))
    return visible


def stamp_windows(windows):
    return [{"start": iso(start), "end": iso(end)} for start, end in windows]


def obscuration(separation, sun, moon):
    if separation >= sun + moon:
        return 0.0
    if separation <= abs(sun - moon):
        return min(1.0, (moon / sun) ** 2)
    x = (separation**2 + sun**2 - moon**2) / (2 * separation)
    y = separation - x
    area = (sun**2 * np.arccos(np.clip(x / sun, -1, 1))
            + moon**2 * np.arccos(np.clip(y / moon, -1, 1))
            - separation * np.sqrt(max(0, sun**2 - x**2)))
    return float(area / (np.pi * sun**2))


def calculate(eph, ts, place, now):
    if now >= END:
        return {"until": iso(END), "solar": [], "lunar": []}
    earth, sun, moon = eph["earth"], eph["sun"], eph["moon"]
    observer = earth + wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])

    def sun_position(t):
        return observer.at(t).observe(sun).apparent()

    def moon_position(t):
        return observer.at(t).observe(moon).apparent()

    def altitude(position, t):
        return position(t).altaz()[0].degrees

    def solar_geometry(t):
        s, m = sun_position(t), moon_position(t)
        return s.separation_from(m).radians, np.arcsin(SUN_RADIUS / s.distance().km), np.arcsin(MOON_RADIUS / m.distance().km)

    def solar_margin(t):
        distance, r_sun, r_moon = solar_geometry(t)
        return r_sun + r_moon - distance

    def solar_inner(t):
        distance, r_sun, r_moon = solar_geometry(t)
        return np.abs(r_sun - r_moon) - distance

    def closest(windows, score):
        best = []
        for start, end in windows:
            times = samples(start, end, 0.5)
            values = score(ts.from_datetimes(times))
            index = int(np.argmin(values))
            best.append((float(values[index]), times[index]))
        return min(best)[1]

    solar, lunar = [], []
    start_t, end_t = ts.from_datetime(now - timedelta(days=1)), ts.from_datetime(END)
    times, phases = almanac.find_discrete(start_t, end_t, almanac.moon_phases(eph))
    for new in times.utc_datetime()[phases == 0]:
        start, end = new - timedelta(hours=8), new + timedelta(hours=8)
        # Reject ordinary new moons before solving local contacts.
        distance, _, _ = solar_geometry(ts.from_datetime(new))
        if distance > np.radians(2.5):
            continue
        outer = crossings(ts, start, end, solar_margin)
        visible = clip_to_horizon(ts, outer, lambda t: altitude(sun_position, t), -0.833, now)
        if not visible:
            continue
        inner = crossings(ts, start, end, solar_inner)

        def normalized(t):
            distance, r_sun, _ = solar_geometry(t)
            return distance / r_sun

        peak = closest(outer, normalized)
        inner_visible = clip_to_horizon(ts, inner, lambda t: altitude(sun_position, t), -0.833, now)
        look = closest(inner_visible or visible, normalized)
        look_time = ts.from_datetime(look)
        separation, r_sun, r_moon = solar_geometry(look_time)
        kind = ("total" if r_moon >= r_sun else "annular") if inner_visible else "partial"
        solar.append({"kind": kind, "peak": iso(peak), "visible": stamp_windows(visible),
                      "central": stamp_windows(inner_visible),
                      "look": describe(sun_position(look_time), look),
                      "coverage": round(100 * obscuration(separation, r_sun, r_moon), 1)})

    def lunar_geometry(t):
        s = (sun - earth).at(t).position.km
        m = (moon - earth).at(t).position.km
        sun_distance, moon_distance = np.linalg.norm(s, axis=0), np.linalg.norm(m, axis=0)
        # Danjon shadow enlargement, as used by Skyfield's lunar eclipse search.
        parallax = ERAD / 1000 * (1.01 / moon_distance + 1 / sun_distance)
        solar_radius = SUN_RADIUS / sun_distance
        return angle_between(-s, m), np.arcsin(MOON_RADIUS / moon_distance), parallax + solar_radius, parallax - solar_radius

    def shadow_margin(phase):
        def margin(t):
            separation, radius, penumbra, umbra = lunar_geometry(t)
            if phase == 0:
                return penumbra + radius - separation
            return umbra + (radius if phase == 1 else -radius) - separation
        return margin

    times, kinds, _ = eclipselib.lunar_eclipses(start_t, end_t, eph)
    for nominal, kind in zip(times.utc_datetime(), kinds):
        start, end = nominal - timedelta(hours=5), nominal + timedelta(hours=5)
        phases = [clip_to_horizon(ts, crossings(ts, start, end, shadow_margin(phase)),
                                  lambda t: altitude(moon_position, t), -0.55, now)
                  for phase in range(int(kind) + 1)]
        if not phases[0]:
            continue
        strongest = max(index for index, spans in enumerate(phases) if spans)
        # A horizon-clipped maximum is often hard to spot in twilight or haze.
        clear = clip_to_horizon(ts, phases[strongest], lambda t: altitude(moon_position, t), 5, now)
        look = closest(clear or phases[strongest], lambda t: lunar_geometry(t)[0])
        lunar.append({"kind": ("penumbral", "partial", "total")[strongest],
                      "globalKind": ("penumbral", "partial", "total")[kind],
                      "peak": iso(nominal), "visible": stamp_windows(phases[0]),
                      "partial": stamp_windows(phases[1]) if len(phases) > 1 else [],
                      "central": stamp_windows(phases[2]) if len(phases) > 2 else [],
                      "look": describe(moon_position(ts.from_datetime(look)), look)})
    return {"until": iso(END), "solar": solar, "lunar": lunar}


def prepare(output, fixture):
    if output.resolve().parent == DEFAULT_STATE.resolve():
        raise ValueError("Eclipse preview needs separate state")
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
        raise SystemExit(f"Eclipse preview: {exc}") from exc
