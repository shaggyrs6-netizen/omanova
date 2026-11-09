"""Append private observations to an atomic, locally locked log."""
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from uuid import uuid4
import fcntl
import json
import os
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from worker import write

FILENAME = "observations.json"


@contextmanager
def locked(directory):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (directory / "observations.lock").open("a") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield directory / FILENAME


def read_log(path):
    try:
        with path.open(encoding="utf-8") as stream:
            data = json.load(stream)
    except FileNotFoundError:
        return {"schema": 1, "entries": []}
    if not isinstance(data, dict) or data.get("schema") != 1 or not isinstance(data.get("entries"), list):
        raise ValueError("Existing log has an unsupported format.")
    return data


def field(payload, key, title, limit, required=True):
    value = payload.get(key, "")
    if not isinstance(value, str) or len(value) > limit:
        raise ValueError(f"{title} must be {limit} characters or fewer.")
    value = value.strip()
    if required and not value:
        raise ValueError(f"Enter {title.lower()}.")
    return value


def observed_time(value):
    try:
        timestamp = datetime.fromisoformat(value)
        if timestamp.utcoffset() is None:
            raise ValueError
    except (ValueError, TypeError) as exc:
        raise ValueError("Enter a valid observation date and time with a time zone.") from exc
    return timestamp


def add_observation(directory, payload):
    if not isinstance(payload, dict):
        raise ValueError("Invalid observation.")
    seen = field(payload, "seen", "What you saw", 120)
    place = field(payload, "place", "Where you were", 120)
    notes = field(payload, "notes", "Notes", 4000, required=False)
    when = observed_time(payload.get("observed"))
    item = {"id": uuid4().hex, "seen": seen, "place": place,
            "notes": notes, "observed": when.isoformat(timespec="minutes")}
    with locked(directory) as path:
        log = read_log(path)
        entries = [item, *log["entries"]]
        entries.sort(key=lambda entry: observed_time(entry["observed"]), reverse=True)
        write(path, {"schema": 1, "entries": entries})
    return item


def main():
    os.umask(0o077)
    directory = Path(sys.argv[1])
    if sys.argv[2] == "init":
        with locked(directory) as path:
            if not path.exists():
                write(path, read_log(path))
    elif sys.argv[2] == "add":
        line = sys.stdin.buffer.readline(32769)
        if len(line) > 32768 or not line.endswith(b"\n"):
            raise ValueError("Observation exceeds the input limit.")
        add_observation(directory, json.loads(line))
    else:
        raise ValueError("Unknown observing log command.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError, KeyError) as exc:
        # Parsing and filesystem errors should not print entry data.
        if isinstance(exc, (OSError, json.JSONDecodeError, UnicodeError, KeyError, TypeError)):
            raise SystemExit("Could not safely read or save the local observing log.") from exc
        raise SystemExit(str(exc)) from exc
