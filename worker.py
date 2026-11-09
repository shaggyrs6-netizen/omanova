"""OMANOVA local worker and settings entry point."""
import argparse
from contextlib import closing, contextmanager
from datetime import UTC, datetime, timedelta
import fcntl
import json
from math import ceil, isfinite
import os
from pathlib import Path
import ssl
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener
from uuid import uuid4

import certifi
from skyfield.api import load, load_file

from astronomy import iso, predict, station_rows, utc
from conditions import FIELDS, classify, opportunities, weather_hours
from observatory.notifications.alerts import decision, deliver, sent_record

ROOT = Path(__file__).resolve().parent
STATIONS_URL = "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=JSON"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
DEFAULT_STATE = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "omasky"
DEMO_NOW = utc("2026-11-09T23:26Z")
EMPTY_SETTINGS = {"profiles": [], "active": None, "temporary": None, "weather": False, "online": False,
                  "alerts": False, "launches": False, "aurora": False, "distance_unit": "km"}
OPT_INS = ("online", "weather", "alerts", "launches", "aurora")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def get_json(url, *, max_bytes=524288):
    opener = build_opener(NoRedirect(), HTTPSHandler(context=ssl.create_default_context(cafile=certifi.where())))
    with opener.open(Request(url, headers={"User-Agent": "OMANOVA/0.1 local prototype"}), timeout=10) as reply:
        if reply.status != 200:
            raise ValueError("Unexpected HTTP status")
        content = reply.read(max_bytes + 1)
    if len(content) > max_bytes:
        raise ValueError("Response exceeds size limit")
    return json.loads(content)


def read(path, default):
    try:
        with path.open("rb") as stream:
            content = stream.read(2097153)
        if len(content) <= 2097152:
            return json.loads(content)
    except (OSError, ValueError):
        pass
    return default


def write(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, mode="w", encoding="utf-8", delete=False) as stream:
        temp = Path(stream.name)
        try:
            json.dump(data, stream, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
            stream.flush()
            os.fsync(stream.fileno())
            os.replace(temp, path)
        finally:
            temp.unlink(missing_ok=True)


@contextmanager
def lock(state):
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (state / "worker.lock").open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def settings_at(state):
    data = read(state / "settings.json", {})
    if not isinstance(data, dict):
        data = {}
    settings = {**EMPTY_SETTINGS, **{key: data[key] for key in EMPTY_SETTINGS if key in data}}
    settings.update({key: settings[key] is True for key in OPT_INS})
    return settings


def location(settings):
    return settings["temporary"] or next(
        (place for place in settings["profiles"] if place["id"] == settings["active"]), None)


def apply_settings(settings, command, values):
    if command in ("save", "temporary"):
        name, lat, lon, elevation = values
        name = " ".join(name.split())
        lat, lon, elevation = float(lat), float(lon), float(elevation or 0)
        if not name or len(name) > 48 or not all(map(isfinite, (lat, lon, elevation))):
            raise ValueError("Enter a name and finite coordinates")
        if not (-90 <= lat <= 90 and -180 <= lon <= 180 and -500 <= elevation <= 9000):
            raise ValueError("Check latitude, longitude and elevation ranges")
        existing = next((p for p in settings["profiles"] if p["name"].casefold() == name.casefold()), None)
        if command == "save" and existing and any(
                existing[key] != value for key, value in (("lat", lat), ("lon", lon), ("elevation", elevation))):
            raise ValueError("That name is already saved. Use a different name or a temporary location.")
        place = existing if command == "save" and existing else {
            "id": uuid4().hex, "name": name, "lat": lat, "lon": lon, "elevation": elevation}
        if command == "temporary":
            settings["temporary"] = place
        else:
            if not existing:
                if len(settings["profiles"]) >= 20:
                    raise ValueError("Saved location limit reached")
                settings["profiles"] = [*settings["profiles"], place]
            settings["active"], settings["temporary"] = place["id"], None
    elif command == "use":
        if not any(p["id"] == values[0] for p in settings["profiles"]):
            raise ValueError("Unknown saved location")
        settings["active"], settings["temporary"] = values[0], None
    elif command in OPT_INS:
        settings[command] = values[0] == "on"
    elif command == "distance-unit":
        if values[0] not in ("km", "mi"):
            raise ValueError("Choose kilometres or miles")
        settings["distance_unit"] = values[0]


def forecast_key(place):
    return f"{place['lat']:.2f},{place['lon']:.2f}"


def update_source(cache, now, period, fetch, validate, *, stop_on_http=False):
    if cache.get("blocked"):
        return
    try:
        if cache.get("next") and utc(cache["next"]) > now:
            return
    except (TypeError, ValueError):
        pass
    try:
        data = fetch()
        validate(data)
    except HTTPError as exc:
        cache["error"] = f"HTTP {exc.code}"
        exc.close()
        if stop_on_http:
            cache["blocked"] = True
            return
        retry = exc.headers.get("Retry-After", "")
        if retry.isascii() and retry.isdigit() and len(retry) <= 9:
            period = max(period, timedelta(seconds=int(retry)))
        elif retry:
            from email.utils import parsedate_to_datetime
            try:
                period = max(period, parsedate_to_datetime(retry) - now)
            except (TypeError, ValueError, OverflowError):
                pass
    except (OSError, ValueError, TypeError, KeyError, OverflowError):
        cache["error"] = "Source unavailable or response invalid"
    else:
        cache.update(data=data, fetched=iso(now), error="")
    cache["next"] = iso(now + period)


def build_snapshot(state, fixture=False):
    now = DEMO_NOW if fixture else datetime.now(UTC)
    settings = settings_at(state)
    place = location(settings)
    orbit_path, weather_path = state / "orbit.json", state / "weather.json"
    orbit, weather = read(orbit_path, {}), read(weather_path, {})
    if not isinstance(orbit, dict):
        orbit = {}
    if not isinstance(weather, dict):
        weather = {}
    events, hours = [], {}
    ts = load.timescale(builtin=True)
    if fixture:
        orbit = {"data": read(ROOT / "tests/fixtures/stations.json", [])}
    elif settings["online"] and place:
        before = orbit.copy()
        update_source(orbit, now, timedelta(hours=2), lambda: get_json(STATIONS_URL),
                      lambda data: station_rows(data, ts), stop_on_http=True)
        if orbit != before:
            write(orbit_path, orbit)

    if place and settings["weather"]:
        key = forecast_key(place)
        if weather.get("key") != key:
            weather = {"key": key}
        if settings["online"] and not fixture:
            lat, lon = key.split(",")
            query = urlencode({"latitude": lat, "longitude": lon, "hourly": ",".join(FIELDS),
                               "timezone": "GMT", "forecast_days": 5})
            before = weather.copy()
            update_source(weather, now, timedelta(hours=3), lambda: get_json(f"{FORECAST_URL}?{query}"),
                          weather_hours)
            if weather != before:
                write(weather_path, weather)
        if weather.get("data"):
            try:
                hours = weather_hours(weather["data"])
            except (ValueError, TypeError, KeyError):
                weather["error"] = "Cached forecast invalid"

    status = "Set a manual observing location"
    if place:
        status = "Enable orbital downloads or load a fixture" if not settings["online"] else "Waiting for orbital elements"
        if orbit.get("error"):
            status = f"Orbital refresh paused · {orbit['error']}" if orbit.get("blocked") else f"Orbital refresh · {orbit['error']}"
        if orbit.get("data"):
            try:
                with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
                    events = predict(orbit["data"], ts, eph, place, now)
                if not orbit.get("error"):
                    status = "Predictions ready" if events else "No passes with usable elements in the next three days"
            except (OSError, ValueError, TypeError, KeyError, OverflowError):
                status = "Check the ephemeris and orbital cache"
    for event in events:
        for window in event["windows"]:
            window["conditions"] = classify(window, hours, weather.get("fetched"), now, settings["weather"])
    snapshot = {"schema_version": 1, "generated": iso(now), "demo": fixture, "status": status,
                "place": place, "settings": settings, "orbit_fetched": orbit.get("fetched"),
                "weather_fetched": weather.get("fetched") if hours else None,
                "weather_error": weather.get("error", "") if settings["weather"] else "",
                "events": events, "candidates": opportunities(events, now)}
    write(state / "snapshot.json", snapshot)
    return snapshot


def check_station_alerts(state, snapshot, now, notify=deliver):
    if snapshot["demo"] or snapshot["settings"].get("alerts") is not True:
        return
    ledger = state / "station-alerts.json"
    history = read(ledger, [])
    if not isinstance(history, list):
        return
    for event in snapshot["events"]:
        for window in event["windows"]:
            if decision(event, window, now, True, history):
                continue
            minutes = ceil((utc(window["start"]["time"]) - now).total_seconds() / 60)
            if notify(event, window, minutes):
                history = [record for record in history if utc(record["set"]) > now - timedelta(days=2)]
                history.append(sent_record(event))
                write(ledger, history)


def watch(state, fixture):
    retry_delay = 15
    while True:
        try:
            with lock(state):
                snapshot = build_snapshot(state, fixture)
                if not fixture:
                    check_station_alerts(state, snapshot, datetime.now(UTC))
            print(snapshot["status"], flush=True)
        except (OSError, ValueError) as exc:
            print(f"Refresh failed: {exc}. Retrying in {retry_delay} seconds.",
                  file=sys.stderr, flush=True)
            time.sleep(retry_delay)
            retry_delay = min(retry_delay * 2, 300)
        else:
            retry_delay = 15
            time.sleep(60)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--fixture", action="store_true", help="Use frozen elements and never fetch")
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("refresh", "watch", "demo", "resume-orbits"):
        commands.add_parser(command)
    for command in ("save", "temporary"):
        sub = commands.add_parser(command)
        for field in ("name", "lat", "lon", "elevation"):
            sub.add_argument(field)
    commands.add_parser("use").add_argument("id")
    for command in OPT_INS:
        commands.add_parser(command).add_argument("value", choices=("on", "off"))
    commands.add_parser("distance-unit").add_argument("value", choices=("km", "mi"))
    args = parser.parse_args()
    if args.command == "demo" and not args.fixture:
        parser.error("demo requires --fixture and a separate preview state directory")
    if args.fixture and args.state.resolve() == DEFAULT_STATE.resolve():
        parser.error("--fixture requires a separate --state directory")
    os.umask(0o077)
    try:
        if args.command == "watch":
            watch(args.state, args.fixture)
            return 0
        with lock(args.state):
            settings = settings_at(args.state)
            if args.command == "demo" and not location(settings):
                apply_settings(settings, "save", ("Nashville demo", "36.1627", "-86.7816", "0"))
                apply_settings(settings, "save", ("Sydney demo", "-33.87", "151.21", "0"))
                apply_settings(settings, "use", (settings["profiles"][0]["id"],))
                write(args.state / "settings.json", settings)
            elif args.command == "resume-orbits":
                orbit_path = args.state / "orbit.json"
                orbit = read(orbit_path, {})
                orbit.pop("blocked", None)
                write(orbit_path, orbit)
            elif args.command not in ("refresh", "demo"):
                if args.command in ("save", "temporary"):
                    values = (args.name, args.lat, args.lon, args.elevation)
                else:
                    values = (args.id if args.command == "use" else args.value,)
                apply_settings(settings, args.command, values)
                write(args.state / "settings.json", settings)
                if args.command == "distance-unit":
                    path = args.state / "snapshot.json"
                    snapshot = read(path, {})
                    if isinstance(snapshot, dict) and isinstance(snapshot.get("settings"), dict):
                        snapshot["settings"]["distance_unit"] = settings["distance_unit"]
                        write(path, snapshot)
                    return 0
            snapshot = build_snapshot(args.state, args.fixture)
            print(snapshot["status"], flush=True)
        return 0
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
