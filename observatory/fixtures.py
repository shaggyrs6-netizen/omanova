"""Prepare an offline observatory snapshot using the real prediction worker."""
from datetime import timedelta
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from astronomy import iso
from worker import (DEFAULT_STATE, DEMO_NOW, apply_settings, build_snapshot,
                    forecast_key, location, lock, settings_at, write)


def prepare(state):
    if state.resolve() == DEFAULT_STATE.resolve():
        raise ValueError("Use a separate fixture state directory")
    with lock(state):
        settings = settings_at(state)
        apply_settings(settings, "save", ("Nashville fixture", "36.1627", "-86.7816", "0"))
        settings.update(online=False, weather=True)
        write(state / "settings.json", settings)
        start = DEMO_NOW.replace(minute=0, second=0)
        write(state / "weather.json", {
            "key": forecast_key(location(settings)),
            "fetched": iso(DEMO_NOW - timedelta(minutes=15)),
            "data": {"hourly": {
                "time": [iso(start + timedelta(hours=index)) for index in range(4)],
                "cloud_cover": [18, 22, 24, 28],
                "cloud_cover_low": [6, 9, 11, 13],
                "cloud_cover_mid": [4, 6, 8, 8],
                "cloud_cover_high": [16, 18, 18, 20],
                "visibility": [18000, 16000, 16000, 15000],
                "precipitation": [0, 0, 0, 0],
                "weather_code": [1, 1, 1, 1],
                "wind_speed_10m": [6, 8, 8, 10],
            }},
        })
        result = build_snapshot(state, fixture=True)
        if not result["candidates"]:
            raise ValueError("No fixture viewing opportunity")


if __name__ == "__main__":
    prepare(Path(sys.argv[1]))
