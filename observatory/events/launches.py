"""Preview-only Launch Library 2 schedule cache. Sends no observer data."""
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import urlparse
from uuid import UUID
import os
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from astronomy import iso, utc
from worker import DEFAULT_STATE, DEMO_NOW, get_json, lock, read, settings_at, update_source, write

BASE = "https://ll.thespacedevs.com/2.3.0/launches/"
FEED = BASE + "upcoming/?mode=detailed&limit=10&hide_recent_previous=true"


def obj(value):
    return value if isinstance(value, dict) else {}


def label(value, fallback="Unknown"):
    return " ".join(value.split())[:180] if isinstance(value, str) and value.strip() else fallback


def timestamp(value):
    try:
        return iso(utc(value))
    except (TypeError, ValueError, OverflowError):
        return None


def stream_url(value):
    if not isinstance(value, str) or len(value) > 1024 or any(c.isspace() for c in value):
        return None
    try:
        url = urlparse(value)
        return value if url.scheme == "https" and url.hostname and not url.username and not url.password else None
    except ValueError:
        return None


def normalise(payload):
    rows = obj(payload).get("results")
    if not isinstance(rows, list) or len(rows) > 10:
        raise ValueError("Unexpected launch schedule")
    result = {}
    for raw in rows:
        row = obj(raw)
        try:
            event_id = str(UUID(row.get("id", "")))
        except (ValueError, AttributeError, TypeError):
            continue
        status = obj(row.get("status"))
        precision = obj(row.get("net_precision")).get("abbrev")
        pad = obj(row.get("pad"))
        rocket = obj(obj(row.get("rocket")).get("configuration"))
        mission = obj(row.get("mission"))
        videos = row.get("vid_urls")
        links = [stream_url(obj(video).get("url")) for video in videos[:12]] if isinstance(videos, list) else []
        result[event_id] = {
            "id": event_id, "name": label(row.get("name"), "Unnamed launch"),
            "provider": label(obj(row.get("launch_service_provider")).get("name")),
            "rocket": label(rocket.get("full_name") or rocket.get("name")),
            "mission": label(mission.get("name"), "Mission details unavailable"),
            "site": label(pad.get("name"), "Launch site unavailable"),
            "region": label(obj(pad.get("location")).get("name"), ""),
            "status": label(status.get("name"), "Status unavailable"), "statusId": status.get("id"),
            "net": timestamp(row.get("net")), "precision": label(precision, ""),
            "windowStart": timestamp(row.get("window_start")), "windowEnd": timestamp(row.get("window_end")),
            "source": BASE + event_id + "/", "stream": next((url for url in links if url), None),
        }
    if rows and not result:
        raise ValueError("No valid launch records")
    return list(result.values())


def prepare(state, fixture, observer_state=None):
    os.umask(0o077)
    now = DEMO_NOW if fixture else datetime.now(UTC)
    enabled = not fixture and settings_at(observer_state or DEFAULT_STATE)["launches"]
    with lock(state):
        if fixture:
            rows = normalise(read(Path(__file__).with_name("launch-fixture.json"), {}))
            cache = {"fetched": iso(now), "error": ""}
        else:
            file = state / "launch-cache-detailed.json"
            cache = obj(read(file, {}))
            before = cache.copy()
            if enabled:
                update_source(cache, now, timedelta(hours=1), lambda: get_json(FEED), normalise)
            if cache != before:
                write(file, cache)
            rows = normalise(cache["data"]) if "data" in cache else []
        # A past exact window should not remain an upcoming launch after a cache hit.
        active = [row for row in rows if row["statusId"] not in (3, 4, 6, 7) and not (
            row["precision"] in ("SEC", "MIN", "HR") and row["statusId"] == 1
            and (row["windowEnd"] or row["net"]) and utc(row["windowEnd"] or row["net"]) < now)]
        write(state / "launches.json", {
            "fixture": fixture, "enabled": enabled, "fetched": cache.get("fetched"), "error": cache.get("error", ""),
            "launches": active,
        })


if __name__ == "__main__":
    prepare(Path(sys.argv[1]), sys.argv[2] == "fixture")
