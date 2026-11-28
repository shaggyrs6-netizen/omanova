"""Weather assessment and bar selection for station passes."""
from datetime import timedelta
from math import isfinite
from astronomy import utc

FIELDS = ("cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
          "visibility", "precipitation", "weather_code", "wind_speed_10m")


ATMOSPHERE_WINDS = ("wind_speed_850hPa", "wind_speed_200hPa")
OPTIONAL_FIELDS = ("temperature_2m", "dew_point_2m", "relative_humidity_2m") + ATMOSPHERE_WINDS
OPTIONAL_RANGES = {"relative_humidity_2m": (0, 100), **dict.fromkeys(ATMOSPHERE_WINDS, (0, 450))}
FORECAST_FIELDS = FIELDS + OPTIONAL_FIELDS


def dew_risk(row):
    temperature, dew_point = (row.get(key) for key in OPTIONAL_FIELDS[:2])
    if temperature is None or dew_point is None:
        return None
    gap = temperature - dew_point
    return "High" if gap <= 2 else "Possible" if gap <= 4 else "Low"


def window_dew_risk(rows):
    labels = [dew_risk(row) for row in rows]
    if "High" in labels:
        return "High"
    if "Possible" in labels:
        return "Possible"
    return "Low" if labels and None not in labels else None


def weather_hours(payload):
    raw = payload["hourly"]
    times = raw["time"]
    if not isinstance(times, list) or not 1 <= len(times) <= 192:
        raise ValueError("Unexpected weather horizon")
    if any(not isinstance(raw[k], list) or len(raw[k]) != len(times) for k in FIELDS):
        raise ValueError("Unexpected weather fields")
    result = {}
    for index, time in enumerate(times):
        stamp = utc(time)
        if stamp.minute or stamp.second or stamp in result:
            raise ValueError("Unexpected weather timestamp")
        row = {key: raw[key][index] for key in FIELDS}
        for key, value in row.items():
            if value is None:
                continue
            ceiling = 100 if key.startswith("cloud_cover") or key == "weather_code" else 300000
            if type(value) not in (int, float) or not isfinite(value) or not 0 <= value <= ceiling:
                raise ValueError("Unexpected weather value")
        # Keep old caches and forecasts with missing optional variables usable.
        for key in OPTIONAL_FIELDS:
            values = raw.get(key)
            value = values[index] if isinstance(values, list) and len(values) == len(times) else None
            minimum, maximum = OPTIONAL_RANGES.get(key, (-100, 70))
            row[key] = value if type(value) in (int, float) and minimum <= value <= maximum else None
        result[stamp] = row
    return result


def optical_context(row):
    """Coarse weather indicators, independent of the pass verdict."""
    surface, lower, upper = (row.get(key) for key in ("wind_speed_10m", *ATMOSPHERE_WINDS))
    cloud, humidity, visibility, rain = (row.get(key) for key in
        ("cloud_cover", "relative_humidity_2m", "visibility", "precipitation"))
    seeing = None
    if None not in (surface, lower, upper):
        if surface >= 28 or lower >= 65 or upper >= 130:
            seeing = "Higher turbulence risk"
        elif surface <= 12 and lower <= 30 and upper <= 75:
            seeing = "Lower turbulence risk"
        else:
            seeing = "Moderate turbulence risk"
    transparency = None
    if None not in (cloud, humidity, visibility, rain):
        if cloud >= 80 or rain >= 0.5 or visibility < 5000:
            transparency = "Obscured"
        elif cloud <= 20 and rain == 0 and humidity <= 75 and visibility >= 15000:
            transparency = "Clear-air potential"
        else:
            transparency = "Reduced clarity"
    return {"seeing": seeing, "transparency": transparency, "surfaceWind": surface,
            "lowerWind": lower, "upperWind": upper, "cloud": cloud,
            "humidity": humidity, "visibility": visibility}

def classify(window, hours, fetched, now, enabled):
    if not enabled:
        return {"label": "Uncertain", "reason": "Weather is off", "hours": []}
    if not fetched or not timedelta(0) <= now - utc(fetched) < timedelta(hours=6):
        return {"label": "Uncertain", "reason": "Forecast missing or expired", "hours": []}
    start = utc(window["start"]["time"])
    end = utc(window["end"]["time"])
    hour = start.replace(minute=0, second=0, microsecond=0)
    expected = [hour, hour + timedelta(hours=1)]
    if end - start > timedelta(days=3):
        return {"label": "Uncertain", "reason": "Viewing window exceeds forecast assessment limit", "hours": []}
    while end > expected[-1]:
        expected.append(expected[-1] + timedelta(hours=1))
    rows = [{"time": time.isoformat(), **hours[time]} for time in expected if time in hours]
    result = {"fetched": fetched, "hours": rows,
              "dewRisk": window_dew_risk(rows) if len(rows) == len(expected) else None}
    required = ("cloud_cover", "visibility", "precipitation")
    if len(rows) < len(expected) or any(row[k] is None for row in rows for k in required):
        return dict(result, label="Uncertain", reason="Forecast incomplete for the viewing window")
    cloud = max(row["cloud_cover"] for row in rows)
    visibility = min(row["visibility"] for row in rows)
    rain = max(row["precipitation"] for row in rows)
    if cloud >= 80 or rain >= 0.5 or visibility < 4000:
        return dict(result, label="Poor", reason="Heavy cloud, precipitation or low visibility in the window")
    if cloud <= 30 and rain == 0 and visibility >= 10000:
        return dict(result, label="Favourable", reason="Low cloud cover and good visibility in the window")
    return dict(result, label="Mixed", reason="Some cloud, precipitation or reduced visibility")


def opportunities(events, now):
    candidates = []
    quality = {"Favourable": 25, "Mixed": 0, "Uncertain": -15}
    for event in events:
        if event["confidence"] == "Stale orbit":
            continue
        for window in event["windows"]:
            start, end = (utc(window[key]["time"]) for key in ("start", "end"))
            if end <= now or start > now + timedelta(hours=24):
                continue
            label = window["conditions"]["label"]
            if label not in quality:
                continue
            hours = max(0, (start - now).total_seconds() / 3600)
            score = quality[label] + window["peak"]["el"] / 3 - hours * 3
            if start <= now:
                score += 100
            candidates.append((score, start, event["id"], window))
    candidates.sort(key=lambda item: (-item[0], item[1]))
    return [{"id": event_id, "start": window["start"]["time"], "end": window["end"]["time"],
             "conditions": window["conditions"]["label"]} for _, _, event_id, window in candidates]
