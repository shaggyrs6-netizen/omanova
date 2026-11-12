"""Weather assessment and bar selection for station passes."""
from datetime import timedelta
from math import isfinite
from astronomy import utc

FIELDS = ("cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
          "visibility", "precipitation", "weather_code", "wind_speed_10m")


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
        result[stamp] = row
    return result


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
    result = {"fetched": fetched, "hours": rows}
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
