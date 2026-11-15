"""Append private observations to an atomic, locally locked log."""
from contextlib import contextmanager
from datetime import datetime, UTC
from pathlib import Path
from uuid import uuid4
import csv
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



def spreadsheet_cell(value):
    # Quoting alone does not stop spreadsheet formula evaluation.
    if value.startswith(("\t", "\r", "\n")) or value.lstrip().startswith(("=", "+", "-", "@")):
        return "'" + value
    return value


def export_csv(directory):
    """Export a validated snapshot to a unique private file; never modify the log."""
    with locked(directory) as path:
        data = read_log(path)
        rows = []
        for entry in data['entries']:
            if not isinstance(entry, dict):
                raise ValueError("The saved log contains an invalid entry. No export was created.")
            observed_time(entry.get('observed'))
            for key, title, limit, required in [('id', 'Entry identifier', 128, True),
                                                ('seen', 'What you saw', 120, True),
                                                ('place', 'Where you were', 120, True),
                                                ('notes', 'Notes', 4000, False)]:
                field(entry, key, title, limit, required)
            rows.append([entry['id'], entry['observed'], entry['seen'], entry['place'], entry.get('notes', '')])
    exports = directory / 'exports'
    if exports.is_symlink():
        raise ValueError("The export folder is a symbolic link. Review it before exporting.")
    exports.mkdir(mode=0o700, exist_ok=True)
    filename = 'omanova-observations-' + datetime.now(UTC).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid4().hex[:12] + '.csv'
    target = exports / filename
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(target, flags, 0o600)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8-sig', newline='') as stream:
            writer = csv.writer(stream, quoting=csv.QUOTE_ALL, lineterminator='\r\n')
            writer.writerow(['id', 'observed', 'seen', 'place', 'notes'])
            writer.writerows([[spreadsheet_cell(value) for value in row] for row in rows])
            stream.flush()
            os.fsync(stream.fileno())
    except BaseException:
        target.unlink(missing_ok=True)  # Only the unique file created by this export.
        raise
    return {'path': str(target), 'count': len(rows), 'spreadsheetEscaping': True}

def main():
    os.umask(0o077)
    directory = Path(sys.argv[1])
    if sys.argv[2] == "init":
        with locked(directory) as path:
            if not path.exists():
                write(path, read_log(path))
    elif sys.argv[2] == "export-csv":
        print(json.dumps(export_csv(directory)))
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
