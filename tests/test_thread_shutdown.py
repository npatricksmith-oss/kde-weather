#!/usr/bin/env python
"""Regression tests for background-thread teardown crashes.

These guard two bugs where a still-running QThread could be garbage-collected,
making Qt abort with "QThread: Destroyed while thread is still running" (SIGABRT):

  1. quitting the app while a forecast request is in-flight
     -- fixed by AppController.shutdown(), called from main.py
  2. a rapid second refresh dropping the first request's still-running thread
     -- fixed by tracking every in-flight pair in AppController._active

The project has no test framework, so this runs standalone:

    python tests/test_thread_shutdown.py          # if kde-weather is installed
    PYTHONPATH=src python tests/test_thread_shutdown.py   # from a source checkout

How it works: a crash surfaces as a non-zero subprocess exit (134 = SIGABRT),
which a normal assertion inside the process could never catch. So each scenario
runs in its OWN subprocess and we assert it exits 0. Each child uses:
  - an isolated $HOME so the real settings.json is never touched,
  - a stubbed, slow network call so a worker is reliably in-flight without
    needing real network access,
  - the offscreen Qt platform so it runs headless (CI, no display).
"""
import os
import subprocess
import sys
import tempfile

SCENARIOS = ["quit-inflight", "concurrent-refresh"]


def _run_scenario(name):
    """Child entry point: exercise one teardown scenario, then exit.

    Returns the process exit code to propagate. A crash won't return here at
    all -- the process aborts -- which is exactly what the parent detects.
    """
    import time

    from PySide6.QtCore import QTimer
    from PySide6.QtWidgets import QApplication

    # Stub the blocking HTTP calls with a slow sleep so the worker thread is
    # guaranteed to still be running when we quit / refresh again. ForecastWorker
    # looks the name up in the worker module's globals at call time, so rebinding
    # it here is enough; no real network is touched.
    from kde_weather.backend.api import worker

    def slow_forecast(lat, lon):
        time.sleep(2.0)
        return {"hourly": {}, "daily": {}}

    def slow_geocode(query, count=5):
        time.sleep(2.0)
        return []

    worker.fetch_forecast = slow_forecast
    worker.fetch_geocode = slow_geocode

    from kde_weather.backend.app_controller import AppController

    app = QApplication([])
    ctrl = AppController()
    # Ensure there's an active location so refresh() actually spawns a worker.
    if ctrl._settings.activeLocation is None:
        ctrl._settings.addLocation("Test City", 0.0, 0.0)

    if name == "quit-inflight":
        ctrl.refresh()
        QTimer.singleShot(200, app.quit)  # quit while the request is in-flight
    elif name == "concurrent-refresh":
        import gc

        for i in range(8):
            QTimer.singleShot(20 * i, ctrl.refresh)  # hammer refresh()
        QTimer.singleShot(200, gc.collect)  # surface any dropped running thread
        QTimer.singleShot(400, gc.collect)
        QTimer.singleShot(600, app.quit)
    else:
        raise SystemExit(f"unknown scenario {name!r}")

    rc = app.exec()
    ctrl.shutdown()  # the fix under test: join worker threads before teardown
    del ctrl
    del app
    return rc


def main():
    # Child invocation: `python <this> _child <scenario>`.
    if len(sys.argv) >= 3 and sys.argv[1] == "_child":
        sys.exit(_run_scenario(sys.argv[2]))

    # Parent: run each scenario in its own subprocess with an isolated HOME and
    # a headless Qt platform, then assert a clean (non-crashing) exit.
    src = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "src"))
    failures = []
    for name in SCENARIOS:
        with tempfile.TemporaryDirectory() as home:
            env = dict(os.environ)
            env["HOME"] = home
            env["QT_QPA_PLATFORM"] = "offscreen"
            # Make `import kde_weather` work from a source checkout too.
            env["PYTHONPATH"] = os.pathsep.join(
                p for p in (src, env.get("PYTHONPATH", "")) if p
            )
            proc = subprocess.run(
                [sys.executable, os.path.abspath(__file__), "_child", name],
                env=env,
                capture_output=True,
                text=True,
            )
        ok = proc.returncode == 0
        print(f"[{'PASS' if ok else 'FAIL'}] {name} (exit {proc.returncode})")
        if not ok:
            failures.append(name)
            sys.stdout.write(proc.stdout)
            sys.stderr.write(proc.stderr)

    if failures:
        print(f"\n{len(failures)} scenario(s) failed: {', '.join(failures)}")
        sys.exit(1)
    print(f"\nAll {len(SCENARIOS)} scenarios passed.")


if __name__ == "__main__":
    main()
