"""Eligibility and deduplication for one opt-in station pass alert."""
from datetime import timedelta
from html import escape
import subprocess

from astronomy import DIRECTIONS, STATIONS, utc

LEAD = timedelta(minutes=15)
MAX_FORECAST_AGE = timedelta(hours=6)


def decision(event, window, now, opted_in, history):
    if not opted_in:
        return "Alerts are off."
    if event["source_id"] not in STATIONS or not window:
        return "No potential viewing window."
    if event["confidence"] == "Stale orbit":
        return "Suppressed · orbital elements are stale."

    start, end = utc(window["start"]["time"]), utc(window["end"]["time"])
    if now >= end:
        return "Suppressed · the viewing window has ended."
    if now >= start:
        return "Suppressed · the viewing window has already started."
    if start - now > LEAD:
        return "Waiting · more than 15 minutes to the viewing window."

    forecast = window["conditions"]
    fetched = forecast.get("fetched")
    if not fetched or not timedelta(0) <= now - utc(fetched) < MAX_FORECAST_AGE:
        return "Suppressed · the event forecast is missing or expired."
    if forecast["label"] != "Favourable":
        return "Suppressed · forecast is " + forecast["label"].lower() + "."

    rise, setting = utc(event["start"]), utc(event["end"])
    if any(
        sent["station"] == event["source_id"] and sent["location"] == event["location_id"]
        and utc(sent["rise"]) < setting and rise < utc(sent["set"])
        for sent in history
    ):
        return "Suppressed · this pass already sent an alert."
    return None


def sent_record(event):
    return {"station": event["source_id"], "location": event["location_id"],
            "rise": event["start"], "set": event["end"]}


def deliver(event, window, minutes, *, preview_place=None, send=subprocess.run):
    station = STATIONS[event["source_id"]]
    first = window["start"]
    direction = first["direction"] if first["direction"] in DIRECTIONS else f"{first['az']:.0f}° true"
    title = f"{station} in {minutes} minute{'s' if minutes != 1 else ''}"
    body = f"Look {direction}, {first['el']:.0f}° above the horizon. Forecast favourable."
    app = "OMANOVA"
    if preview_place:
        title = "[Preview] " + title
        body += f" {preview_place} fixture."
        app += " Preview"
    try:
        send(["/usr/bin/notify-send", f"--app-name={app}", "--urgency=normal",
              "--expire-time=8000", "--", title, escape(body)],
             timeout=5, check=True, capture_output=True)
    except (OSError, subprocess.SubprocessError):
        return False
    return True
