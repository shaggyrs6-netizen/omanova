"""Generate offline scenarios and deliver explicitly requested preview alerts."""
from contextlib import closing
from datetime import timedelta
from pathlib import Path
import argparse
import os
import subprocess
import sys

from skyfield.api import load, load_file

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from astronomy import STATIONS, iso, predict, utc
from observatory.notifications.alerts import LEAD, decision, deliver, sent_record
from worker import lock, read, write

PREVIEW = ROOT / ".preview" / "notifications"
SCENARIOS = ("favourable", "poor", "missing", "stale", "ended")
SITES = {
    25544: {"id": "nashville", "name": "Nashville", "lat": 36.1627, "lon": -86.7816, "elevation": 0},
    48274: {"id": "sydney", "name": "Sydney", "lat": -33.87, "lon": 151.21, "elevation": 0},
}


def prepare(state):
    rows = read(ROOT / "tests/fixtures/stations.json", [])
    clock = utc("2026-11-09T00:00:00Z")
    ts = load.timescale(builtin=True)
    samples = {}
    with closing(load_file(str(ROOT / "assets/de440s.bsp"))) as eph:
        for station, place in SITES.items():
            passes = predict(rows, ts, eph, place, clock, days=1)
            event = next(e for e in passes if e["source_id"] == station and e["windows"])
            sample = {key: event[key] for key in ("source_id", "location_id", "start", "end", "confidence")}
            sample.update(place=place["name"], window=event["windows"][0])
            samples[str(station)] = sample
    write(state / "samples.json", samples)


def scenario_for(sample, scenario):
    event = dict(sample)
    window = dict(event["window"])
    now = utc(window["start"]["time"]) - LEAD
    forecast = {"label": "Favourable", "fetched": iso(now - timedelta(hours=1))}
    if scenario == "poor":
        forecast["label"] = "Poor"
    elif scenario == "missing":
        forecast = {"label": "Uncertain"}
    elif scenario == "stale":
        event["confidence"] = "Stale orbit"
    elif scenario == "ended":
        now = utc(window["end"]["time"]) + timedelta(minutes=1)
    window["conditions"] = forecast
    return event, window, now


def send_preview(state, station, scenario, opted_in, send=subprocess.run):
    with lock(state):
        samples = read(state / "samples.json", {})
        event, window, now = scenario_for(samples[str(station)], scenario)
        ledger = state / "sent.json"
        history = read(ledger, [])
        reason = decision(event, window, now, opted_in, history)
        if reason:
            return reason
        if not deliver(event, window, 15, preview_place=event["place"], send=send):
            return "Desktop notification failed. This pass is still eligible for a retry."
        write(ledger, [*history, sent_record(event)])
        return f"Sent a preview desktop alert for {STATIONS[station]}."


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("state", type=Path)
    command = parser.add_subparsers(dest="command", required=True)
    command.add_parser("prepare")
    attempt = command.add_parser("attempt")
    attempt.add_argument("station", type=int, choices=STATIONS)
    attempt.add_argument("scenario", choices=SCENARIOS)
    attempt.add_argument("consent", choices=("on", "off"))
    args = parser.parse_args()
    state = args.state.resolve()
    if state.parent != PREVIEW.resolve() or not state.name.startswith("trial."):
        parser.error("Use an isolated notification preview directory.")
    os.umask(0o077)
    if args.command == "prepare":
        prepare(state)
    else:
        print(send_preview(state, args.station, args.scenario, args.consent == "on"))


if __name__ == "__main__":
    main()
