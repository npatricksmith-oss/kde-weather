#!/usr/bin/env python
"""Test AppController.selectDay() populates app.dayDetail from cached NWS data.

Runs in a subprocess with an isolated $HOME, offscreen Qt, and stubbed network
(so AppController's startup refresh touches nothing). We seed the NWS cache
directly, call selectDay, and assert dayDetail reflects the parsed day.

    PYTHONPATH=src python tests/test_day_detail.py
"""
import os
import subprocess
import sys
import tempfile


def _child():
    from PySide6.QtWidgets import QApplication

    # Stub the network so the startup refresh and any worker are offline/no-ops.
    from kde_weather.backend.api import worker
    worker.fetch_forecast = lambda lat, lon: {"hourly": {}, "daily": {}}
    worker.fetch_geocode = lambda query, count=5: []

    from kde_weather.backend.app_controller import AppController

    app = QApplication([])
    ctrl = AppController()
    ctrl._settings.addLocation("Test City", 43.0, -76.0)
    loc = ctrl._settings.activeLocation
    key = (loc["lat"], loc["lon"])

    # Seed the per-location NWS cache so selectDay() serves from it (no fetch).
    ctrl._nws_cache[key] = {
        "available": True,
        "periods": [
            {"name": "Wednesday", "isDaytime": True,
             "startTime": "2026-06-17T06:00:00-04:00", "detailedForecast": "Sunny."},
            {"name": "Wednesday Night", "isDaytime": False,
             "startTime": "2026-06-17T18:00:00-04:00", "detailedForecast": "Clear."},
        ],
        "alerts": [{"properties": {
            "event": "Heat Advisory", "severity": "Moderate",
            "headline": "Heat Advisory in effect",
            "description": "Hot.",
            "effective": "2026-06-17T10:00:00-04:00",
            "expires": "2026-06-17T20:00:00-04:00"}}],
    }

    ctrl.selectDay("2026-06-17")
    dd = ctrl._day_detail
    assert dd.selectedDate == "2026-06-17", dd.selectedDate
    assert [p["name"] for p in dd.periods] == ["Wednesday", "Wednesday Night"], dd.periods
    assert dd.periods[0]["text"] == "Sunny.", dd.periods
    assert len(dd.alerts) == 1 and dd.alerts[0]["event"] == "Heat Advisory", dd.alerts
    assert dd.alerts[0]["expiresText"].startswith("until "), dd.alerts

    # Clicking the same day again collapses.
    ctrl.selectDay("2026-06-17")
    assert dd.selectedDate == "", dd.selectedDate

    ctrl.shutdown()
    print("child ok")


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "_child":
        _child()
        return
    src = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "src"))
    with tempfile.TemporaryDirectory() as home:
        env = dict(os.environ)
        env["HOME"] = home
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["PYTHONPATH"] = os.pathsep.join(p for p in (src, env.get("PYTHONPATH", "")) if p)
        proc = subprocess.run([sys.executable, os.path.abspath(__file__), "_child"],
                              env=env, capture_output=True, text=True)
    ok = proc.returncode == 0 and "child ok" in proc.stdout
    print(f"[{'PASS' if ok else 'FAIL'}] selectDay populates dayDetail (exit {proc.returncode})")
    if not ok:
        sys.stdout.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        sys.exit(1)
    print("\nAll 1 passed")


if __name__ == "__main__":
    main()
