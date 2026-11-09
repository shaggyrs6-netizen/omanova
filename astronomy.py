"""Local station geometry. No network access."""
from datetime import UTC, datetime, timedelta
from math import isfinite

import numpy as np
from skyfield.api import EarthSatellite, wgs84

STATIONS = {25544: "ISS", 48274: "Tiangong"}
DIRECTIONS = "N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW".split()
SOURCE = "https://celestrak.org/norad/elements/table.php?GROUP=stations"


def utc(value):
    stamp = datetime.fromisoformat(value)
    return stamp.replace(tzinfo=UTC) if stamp.tzinfo is None else stamp.astimezone(UTC)


def iso(value):
    return value.astimezone(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def station_rows(rows, timescale, *, catalog=STATIONS, require_all=True):
    if not isinstance(rows, list) or len(rows) > 256:
        raise ValueError("Unexpected stations response")
    selected = {}
    for row in rows:
        if not isinstance(row, dict) or type(row.get("NORAD_CAT_ID")) is not int:
            raise ValueError("Invalid catalogue ID")
        number = row["NORAD_CAT_ID"]
        if number not in catalog:
            continue
        epoch = utc(row["EPOCH"])
        if not 1957 <= epoch.year <= 2100:
            raise ValueError("Invalid element epoch")
        for field in ("MEAN_MOTION", "ECCENTRICITY", "INCLINATION", "RA_OF_ASC_NODE",
                      "ARG_OF_PERICENTER", "MEAN_ANOMALY", "BSTAR",
                      "MEAN_MOTION_DOT", "MEAN_MOTION_DDOT"):
            if not isfinite(float(row[field])):
                raise ValueError("Invalid orbital field")
        if not (10 < float(row["MEAN_MOTION"]) < 20 and
                0 <= float(row["ECCENTRICITY"]) < 0.1 and
                0 <= float(row["INCLINATION"]) <= 180):
            raise ValueError("Orbit outside station bounds")
        model = EarthSatellite.from_omm(timescale, row)
        _, _, distance = model.at(model.epoch).radec()
        if not isfinite(float(distance.km)):
            raise ValueError("Invalid orbit")
        if number not in selected or epoch > utc(selected[number]["EPOCH"]):
            selected[number] = row
    if require_all and set(selected) != set(catalog):
        raise ValueError("Station feed missing ISS or Tiangong")
    return selected


def pass_ranges(satellite, site, ts, start, end):
    difference = satellite - site
    rise = start if difference.at(ts.from_datetime(start)).altaz()[0].degrees >= 0 else None
    times, codes = satellite.find_events(site, ts.from_datetime(start), ts.from_datetime(end))
    for time, code in zip(times.utc_datetime(), codes):
        if code == 0:
            rise = time
        elif code == 2 and rise is not None:
            yield rise, time
            rise = None
    if rise is not None:
        yield rise, end


def predict(rows, ts, eph, place, start, days=3, *, catalog=STATIONS, source=SOURCE):
    site = wgs84.latlon(place["lat"], place["lon"], elevation_m=place["elevation"])
    observer = eph["earth"] + site
    stop = start + timedelta(days=days)
    # Pad the search so a pass already in progress retains its original rise.
    scan_start = start - timedelta(minutes=30)
    events = []
    for number, row in station_rows(rows, ts, catalog=catalog, require_all=catalog is STATIONS).items():
        satellite = EarthSatellite.from_omm(ts, row)
        epoch = utc(row["EPOCH"])
        if epoch < start - timedelta(days=7) or epoch > start + timedelta(hours=6):
            continue
        for rise, setting in pass_ranges(satellite, site, ts, scan_start, stop + timedelta(minutes=30)):
            if setting <= start or rise >= stop or rise == scan_start or setting >= stop + timedelta(minutes=30):
                continue
            event = describe(satellite, ts, eph, site, observer, number, epoch, rise, setting, place)
            if event is not None:
                if catalog is not STATIONS:
                    event.update(type="satellite", name=catalog[number], source=source)
                events.append(event)
    return sorted(events, key=lambda event: event["start"])


def describe(satellite, ts, eph, site, observer, number, epoch, rise, setting, place):
    span = (setting - rise).total_seconds()
    offsets = np.linspace(0, span, max(2, int(np.ceil(span / 2)) + 1))
    dates = [rise + timedelta(seconds=float(offset)) for offset in offsets]
    t = ts.from_datetimes(dates)
    altitude, azimuth, _ = (satellite - site).at(t).altaz()
    alt, az = altitude.degrees, azimuth.degrees
    if not np.all(np.isfinite(alt)) or not np.all(np.isfinite(az)):
        return None
    peak = int(np.argmax(alt))
    age = abs((dates[peak] - epoch).total_seconds()) / 3600
    if age > 168:
        return None
    sunlit = satellite.at(t).is_sunlit(eph)
    dark = observer.at(t).observe(eph["sun"]).apparent().altaz()[0].degrees <= -6
    high = alt >= 10
    visible = sunlit & dark & high

    def point(index):
        bearing = round(float(az[index]), 1) % 360
        return {"time": iso(dates[index]), "az": bearing, "el": round(float(alt[index]), 1),
                "direction": DIRECTIONS[int((bearing + 11.25) // 22.5) % 16],
                "visible": bool(visible[index]), "sunlit": bool(sunlit[index]), "sky_dark": bool(dark[index])}

    windows = []
    edges = np.flatnonzero(np.diff(np.r_[False, visible, False]))
    for first, past_last in zip(edges[::2], edges[1::2]):
        last = past_last - 1
        if (dates[last] - dates[first]).total_seconds() >= 10:
            highest = first + int(np.argmax(alt[first:past_last]))
            windows.append({"start": point(first), "peak": point(highest), "end": point(last)})
    if windows:
        reason = "Sunlit station above 10° against a darker sky"
    elif not np.any(high):
        reason = "Pass stays below 10°"
    elif not np.any(high & dark):
        reason = "Sky too bright during the high part of the pass"
    elif not np.any(high & dark & sunlit):
        reason = "Station in Earth’s shadow during the dark part of the pass"
    else:
        reason = "Viewing window shorter than 10 seconds"

    indices = set(range(0, len(dates), 4)) | {0, peak, len(dates) - 1}
    indices.update(int(index) for edge in edges for index in (edge - 1, edge) if 0 <= index < len(dates))
    return {
        "id": f"{number}/{place['id']}/{iso(rise)}", "type": "station", "source": SOURCE,
        "source_id": number, "name": STATIONS.get(number, str(number)), "location_id": place["id"],
        "start": iso(rise), "peak": iso(dates[peak]), "end": iso(setting),
        "duration_s": round(span), "element_epoch": iso(epoch), "epoch_hours": round(age, 1),
        "confidence": "Stale orbit" if age > 72 else "Provisional",
        "status": "potential" if windows else "geometric",
        "rise": point(0), "culmination": point(peak), "set": point(len(dates) - 1),
        "windows": windows, "path": [point(index) for index in sorted(indices)],
        "reason": reason,
    }
