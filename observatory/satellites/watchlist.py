"""Bright-object watchlist with an isolated orbital cache."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import sys
import os

from skyfield.api import load, load_file

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import STATIONS, iso, predict, station_rows, utc
from observing_preferences import preferences
from worker import DEFAULT_STATE, get_json, location, lock, read, settings_at, update_source, write

CATALOG = {**STATIONS, 20580: "Hubble", 27386: "Envisat", 25994: "Terra", 27424: "Aqua", 39766: "ALOS-2"}
SOURCE = "https://celestrak.org/NORAD/elements/table.php?GROUP=visual"
FEED = "https://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=JSON"
MAX_AGE = timedelta(hours=72)


def prepare(output, state, fixture, observer_state=None):
    if output.resolve().parent == DEFAULT_STATE.resolve() or state.resolve() == DEFAULT_STATE.resolve():
        raise ValueError("Watchlist preview needs separate state")
    fixture_state = Path(os.environ["OMASKY_STATE"]) if fixture and os.environ.get("OMASKY_STATE") else None
    settings = settings_at(observer_state or fixture_state or DEFAULT_STATE) if not fixture or observer_state or fixture_state else {}
    place = ({"id": "nashville-fixture", "lat": 36.1627, "lon": -86.7816, "elevation": 0}
             if fixture else location(settings))
    catalog = {row["number"]: row["name"] for row in preferences(settings)["watchlist"]}
    validation_catalog = {**CATALOG, **catalog}
    if not place:
        raise ValueError("Set an observing location in OMANOVA first.")
    now = utc("2026-11-09T13:00:00Z") if fixture else datetime.now(UTC)
    ts = load.timescale(builtin=True)

    def validated(rows):
        result = station_rows(rows, ts, catalog=validation_catalog, require_all=False)
        if not result:
            raise ValueError("Bright-object feed contains no watchlist entries")
        return result

    if fixture:
        cache = {"data": read(Path(__file__).with_name("fixture-elements.json"), [])}
    else:
        with lock(state):
            path = state / "orbit.json"
            cache = read(path, {})
            before = cache.copy()
            if settings["online"]:
                update_source(cache, now, timedelta(hours=2), lambda: get_json(FEED), validated, stop_on_http=True)
            if cache != before:
                write(path, cache)

    available = validated(cache["data"]) if "data" in cache else {}
    issues = []
    if not fixture:
        for number, name in catalog.items():
            if number in CATALOG:
                continue
            with lock(state):
                path = state / ("object-" + str(number) + ".json")
                individual = read(path, {})
                if settings["online"]:
                    update_source(individual, now, timedelta(hours=2),
                        lambda n=number: get_json("https://celestrak.org/NORAD/elements/gp.php?CATNR=" + str(n) + "&FORMAT=JSON"),
                        lambda data, n=number, label=name: station_rows(data, ts, catalog={n:label}), stop_on_http=True)
                    write(path, individual)
                if individual.get("data"):
                    try: available.update(station_rows(individual["data"], ts, catalog={number:name}))
                    except (ValueError, TypeError, KeyError): issues.append("Object data unavailable: " + str(number))
                if individual.get("error"): issues.append(str(number) + ": " + str(individual["error"]))
    available = {number: row for number, row in available.items() if number in catalog}
    usable = {number: row for number, row in available.items()
              if now - MAX_AGE <= utc(row["EPOCH"]) <= now + timedelta(hours=6)}
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        events = predict(list(usable.values()), ts, eph, place, now, catalog=catalog, source=SOURCE)
    windows = []
    for event in events:
        for window in event["windows"]:
            first, last = utc(window["start"]["time"]), utc(window["end"]["time"])
            if first < now or last >= now + timedelta(days=3) or abs(last - utc(event["element_epoch"])) > MAX_AGE:
                continue
            windows.append({**window, "name": event["name"], "number": event["source_id"],
                            "epoch": event["element_epoch"], "brightnessKnown": event["source_id"] in CATALOG})
    windows.sort(key=lambda window: window["start"]["time"])
    targets = [{"name": name, "number": number, "usable": number in usable}
               for number, name in catalog.items()]
    write(output, {"fixture": fixture, "online": settings.get("online", False),
                   "fetched": cache.get("fetched"), "error": cache.get("error"), "source": SOURCE,
                   "targets": targets, "windows": windows, "issues": issues})


if __name__ == "__main__":
    try:
        output, state = map(Path, sys.argv[1:3])
        prepare(output, state, sys.argv[3] == "fixture")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Satellite watchlist: {exc}") from exc
