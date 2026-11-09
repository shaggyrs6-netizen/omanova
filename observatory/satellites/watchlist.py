"""Bright-object watchlist with an isolated orbital cache."""
from contextlib import closing
from datetime import UTC, datetime, timedelta
from pathlib import Path
import sys

from skyfield.api import load, load_file

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import STATIONS, iso, predict, station_rows, utc
from worker import DEFAULT_STATE, get_json, location, lock, read, settings_at, update_source, write

CATALOG = {**STATIONS, 20580: "Hubble", 27386: "Envisat", 25994: "Terra", 27424: "Aqua", 39766: "ALOS-2"}
SOURCE = "https://celestrak.org/NORAD/elements/table.php?GROUP=visual"
FEED = "https://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=JSON"
MAX_AGE = timedelta(hours=72)


def prepare(output, state, fixture):
    if output.resolve().parent == DEFAULT_STATE.resolve() or state.resolve() == DEFAULT_STATE.resolve():
        raise ValueError("Watchlist preview needs separate state")
    settings = settings_at(DEFAULT_STATE) if not fixture else {}
    place = ({"id": "nashville-fixture", "lat": 36.1627, "lon": -86.7816, "elevation": 0}
             if fixture else location(settings))
    if not place:
        raise ValueError("Set an observing location in Omasky first.")
    now = utc("2026-11-09T13:00:00Z") if fixture else datetime.now(UTC)
    ts = load.timescale(builtin=True)

    def validated(rows):
        result = station_rows(rows, ts, catalog=CATALOG, require_all=False)
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
    usable = {number: row for number, row in available.items()
              if now - MAX_AGE <= utc(row["EPOCH"]) <= now + timedelta(hours=6)}
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        events = predict(list(usable.values()), ts, eph, place, now, catalog=CATALOG, source=SOURCE)
    windows = []
    for event in events:
        for window in event["windows"]:
            first, last = utc(window["start"]["time"]), utc(window["end"]["time"])
            if first < now or last >= now + timedelta(days=3) or abs(last - utc(event["element_epoch"])) > MAX_AGE:
                continue
            windows.append({**window, "name": event["name"], "number": event["source_id"],
                            "epoch": event["element_epoch"]})
    windows.sort(key=lambda window: window["start"]["time"])
    targets = [{"name": name, "number": number, "usable": number in usable}
               for number, name in CATALOG.items()]
    write(output, {"fixture": fixture, "online": settings.get("online", False),
                   "fetched": cache.get("fetched"), "error": cache.get("error"), "source": SOURCE,
                   "targets": targets, "windows": windows})


if __name__ == "__main__":
    try:
        output, state = map(Path, sys.argv[1:3])
        prepare(output, state, sys.argv[3] == "fixture")
    except (OSError, ValueError, TypeError, KeyError) as exc:
        raise SystemExit(f"Satellite watchlist: {exc}") from exc
