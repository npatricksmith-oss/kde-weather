# NOAA/NWS Day Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking a day in the 7-Day tab expands a panel showing the US National Weather Service daytime + nighttime narrative for that day plus any hazardous/emergency alerts active on it.

**Architecture:** A new keyless NWS HTTP client (`backend/api/nws.py`) with pure, unit-tested parsing helpers; an `NwsWorker` run on the existing `_spawn`/`_active` thread machinery; a `DayDetail` QObject (`app.dayDetail`) holding the selected day's state; `AppController.selectDay()` fetching-on-click and caching per location; and QML changes making `DayCard` clickable and `DailyView` show a `DayDetailPanel` below the day row.

**Tech Stack:** Python 3.11+, PySide6 (Qt6) QObject/Property/Signal, QML, `requests`. No test framework — standalone `tests/*.py` scripts run with `PYTHONPATH=src python tests/<file>.py` (a non-zero exit means failure).

**Spec:** `docs/superpowers/specs/2026-06-12-noaa-day-detail-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/kde_weather/backend/api/nws.py` | **New.** NWS HTTP client (`fetch_nws_details`) + pure parsing helpers (`periods_for_date`, `alerts_for_date`, `format_expires`). |
| `src/kde_weather/backend/api/worker.py` | **Modify.** Add `NwsWorker`. |
| `src/kde_weather/backend/models/day_detail.py` | **New.** `DayDetail` QObject exposed as `app.dayDetail`. |
| `src/kde_weather/backend/app_controller.py` | **Modify.** Own `DayDetail`, add `selectDay()` + NWS cache + populate logic. |
| `src/kde_weather/qml/theme/Theme.qml` | **Modify.** Add `warning` color for moderate alerts. |
| `src/kde_weather/qml/components/DayCard.qml` | **Modify.** `clicked` signal + `selected` highlight. |
| `src/kde_weather/qml/components/DayDetailPanel.qml` | **New.** Reads `app.dayDetail`; renders heading/states/alerts/narrative. |
| `src/kde_weather/qml/views/DailyView.qml` | **Modify.** Vertical layout: day row + `DayDetailPanel`. |
| `tests/test_nws_parsing.py` | **New.** Tests for the pure helpers + mocked `fetch_nws_details`. |
| `tests/test_day_detail.py` | **New.** Subprocess test: seeded cache → `selectDay` → populated `dayDetail`. |

---

## Task 1: NWS parsing helpers (pure, no network)

**Files:**
- Create: `src/kde_weather/backend/api/nws.py`
- Test: `tests/test_nws_parsing.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_nws_parsing.py`:

```python
#!/usr/bin/env python
"""Tests for the NWS client and its pure parsing helpers.

No framework; run directly:
    PYTHONPATH=src python tests/test_nws_parsing.py
Each test_* function raises AssertionError on failure; the runner reports
results and exits non-zero if any fail.
"""
import os
import sys

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "src")))

from kde_weather.backend.api import nws


def test_periods_for_date_selects_day_and_night():
    periods = [
        {"name": "Wednesday", "isDaytime": True,
         "startTime": "2026-06-17T06:00:00-04:00", "detailedForecast": "Sunny."},
        {"name": "Wednesday Night", "isDaytime": False,
         "startTime": "2026-06-17T18:00:00-04:00", "detailedForecast": "Clear."},
        {"name": "Thursday", "isDaytime": True,
         "startTime": "2026-06-18T06:00:00-04:00", "detailedForecast": "Cloudy."},
    ]
    res = nws.periods_for_date(periods, "2026-06-17")
    assert res["day"]["name"] == "Wednesday", res
    assert res["night"]["name"] == "Wednesday Night", res


def test_periods_for_date_missing_returns_none():
    res = nws.periods_for_date([], "2026-06-17")
    assert res == {"day": None, "night": None}, res


def test_alerts_for_date_includes_overlapping():
    alerts = [{"properties": {
        "event": "Winter Storm Warning",
        "effective": "2026-06-17T12:00:00-04:00",
        "expires": "2026-06-18T06:00:00-04:00"}}]
    res = nws.alerts_for_date(alerts, "2026-06-17")
    assert len(res) == 1 and res[0]["event"] == "Winter Storm Warning", res


def test_alerts_for_date_excludes_outside_window():
    alerts = [{"properties": {
        "event": "Heat Advisory",
        "effective": "2026-06-20T12:00:00-04:00",
        "expires": "2026-06-21T06:00:00-04:00"}}]
    res = nws.alerts_for_date(alerts, "2026-06-17")
    assert res == [], res


def test_format_expires_human_readable():
    assert nws.format_expires("2026-06-18T18:00:00-04:00") == "until Thu 6:00 PM", \
        nws.format_expires("2026-06-18T18:00:00-04:00")
    assert nws.format_expires("") == ""
    assert nws.format_expires("garbage") == ""


def _run():
    tests = [v for k, v in sorted(globals().items())
             if k.startswith("test_") and callable(v)]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except AssertionError as e:
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
    if failed:
        print(f"\n{failed} of {len(tests)} failed")
        sys.exit(1)
    print(f"\nAll {len(tests)} passed")


if __name__ == "__main__":
    _run()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `PYTHONPATH=src python tests/test_nws_parsing.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'kde_weather.backend.api.nws'` (import error before any test runs).

- [ ] **Step 3: Write the helpers**

Create `src/kde_weather/backend/api/nws.py` (helpers only for now; `fetch_nws_details` is added in Task 2):

```python
"""HTTP client + parsing for the US National Weather Service (NWS/NOAA) API.

What: api.weather.gov provides narrative forecasts and active alerts.
Why:  Open-Meteo (the app's primary source) has neither narrative text nor US
      alerts, so this is a second, US-only source used by the 7-Day tab.
How:  fetch_nws_details() (Task 2) does the network flow; the period/alert
      parsing lives in pure helpers here so it can be unit-tested offline.

NWS requires a descriptive User-Agent header or it returns 403.
"""
from datetime import datetime, timedelta

import requests

# NWS asks for a User-Agent identifying the app (and ideally a contact).
# See https://www.weather.gov/documentation/services-web-api
NWS_USER_AGENT = "kde-weather (github.com/npatricksmith-oss/kde-weather)"
_HEADERS = {"User-Agent": NWS_USER_AGENT, "Accept": "application/geo+json"}

POINTS_URL = "https://api.weather.gov/points/{lat},{lon}"
ALERTS_URL = "https://api.weather.gov/alerts/active"


def _parse_iso(ts):
    """Parse an NWS ISO-8601 timestamp like '2026-06-12T18:00:00-04:00'.

    Returns a timezone-aware datetime, or None when ts is falsy/unparseable.
    datetime.fromisoformat handles the trailing offset on Python 3.11+.
    """
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts)
    except ValueError:
        return None


def periods_for_date(periods, date_str):
    """Return {'day': period|None, 'night': period|None} for a YYYY-MM-DD date.

    A period belongs to date_str when the local date of its startTime matches.
    The daytime period has isDaytime True; the nighttime period False. If more
    than one of a kind matches (shouldn't happen), the first is kept.
    """
    result = {"day": None, "night": None}
    for p in periods:
        start = _parse_iso(p.get("startTime"))
        if start is None or start.strftime("%Y-%m-%d") != date_str:
            continue
        slot = "day" if p.get("isDaytime") else "night"
        if result[slot] is None:
            result[slot] = p
    return result


def alerts_for_date(alerts, date_str):
    """Return alert *properties* whose active window overlaps the local day.

    Accepts either raw GeoJSON features ({'properties': {...}}) or already-
    unwrapped property dicts. The day is [date 00:00, date+1 00:00). The alert
    window is [effective|onset, expires|ends]; a missing start means "already
    active", a missing end means "open-ended". Times are compared on wall-clock
    (tzinfo dropped), which matches how NWS issues alerts in local time.
    """
    day_start = datetime.fromisoformat(date_str + "T00:00:00")
    day_end = day_start + timedelta(days=1)
    out = []
    for a in alerts:
        props = a.get("properties", a)
        start = _parse_iso(props.get("effective") or props.get("onset"))
        end = _parse_iso(props.get("expires") or props.get("ends"))
        s = start.replace(tzinfo=None) if start else None
        e = end.replace(tzinfo=None) if end else None
        if e is not None and e < day_start:
            continue
        if s is not None and s >= day_end:
            continue
        out.append(props)
    return out


def format_expires(ts):
    """Human-friendly end time, e.g. 'until Thu 6:00 PM'. '' if unparseable."""
    dt = _parse_iso(ts)
    if dt is None:
        return ""
    return dt.strftime("until %a %-I:%M %p")
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `PYTHONPATH=src python tests/test_nws_parsing.py`
Expected: PASS — `All 5 passed`.

- [ ] **Step 5: Commit**

```bash
git add src/kde_weather/backend/api/nws.py tests/test_nws_parsing.py
git commit -m "Add NWS parsing helpers (periods/alerts by date)"
```

---

## Task 2: NWS HTTP client `fetch_nws_details`

**Files:**
- Modify: `src/kde_weather/backend/api/nws.py`
- Test: `tests/test_nws_parsing.py`

- [ ] **Step 1: Add failing tests**

Append these test functions to `tests/test_nws_parsing.py` (above `_run()`):

```python
class _FakeResp:
    def __init__(self, status=200, payload=None):
        self.status_code = status
        self._payload = payload or {}

    def raise_for_status(self):
        if self.status_code >= 400:
            raise AssertionError(f"raise_for_status called on {self.status_code}")

    def json(self):
        return self._payload


def _install_fake_get(mapping):
    """Replace nws.requests.get with a URL-dispatching fake; return a restore fn.

    `mapping` maps a substring of the URL to a _FakeResp.
    """
    orig = nws.requests.get

    def fake_get(url, *args, **kwargs):
        for needle, resp in mapping.items():
            if needle in url:
                return resp
        raise AssertionError(f"unexpected URL {url!r}")

    nws.requests.get = fake_get
    return lambda: setattr(nws.requests, "get", orig)


def test_fetch_unavailable_when_point_404():
    restore = _install_fake_get({"/points/": _FakeResp(status=404)})
    try:
        res = nws.fetch_nws_details(0.0, 0.0)
    finally:
        restore()
    assert res == {"available": False, "periods": [], "alerts": []}, res


def test_fetch_happy_path_returns_periods_and_alerts():
    mapping = {
        "/points/": _FakeResp(payload={
            "properties": {"forecast": "https://api.weather.gov/gridpoints/X/1,1/forecast"}}),
        "/forecast": _FakeResp(payload={
            "properties": {"periods": [{"name": "Today", "isDaytime": True}]}}),
        "/alerts/active": _FakeResp(payload={
            "features": [{"properties": {"event": "Test Warning"}}]}),
    }
    restore = _install_fake_get(mapping)
    try:
        res = nws.fetch_nws_details(43.0, -76.0)
    finally:
        restore()
    assert res["available"] is True, res
    assert res["periods"][0]["name"] == "Today", res
    assert res["alerts"][0]["properties"]["event"] == "Test Warning", res
```

- [ ] **Step 2: Run to verify failure**

Run: `PYTHONPATH=src python tests/test_nws_parsing.py`
Expected: FAIL — `AttributeError: module 'kde_weather.backend.api.nws' has no attribute 'fetch_nws_details'`.

- [ ] **Step 3: Implement `fetch_nws_details`**

Append to `src/kde_weather/backend/api/nws.py`:

```python
def fetch_nws_details(lat, lon):
    """Fetch NWS day/night periods + active alerts for a point.

    Returns {"available": bool, "periods": list, "alerts": list}.

    available is False when the point is outside NWS coverage (US-only): the
    points endpoint returns 404 or yields no forecast URL. Any other HTTP or
    network error raises (NwsWorker turns it into an error state). The three
    requests all send the required NWS User-Agent header.
    """
    points = requests.get(
        POINTS_URL.format(lat=lat, lon=lon), headers=_HEADERS, timeout=15
    )
    if points.status_code == 404:
        return {"available": False, "periods": [], "alerts": []}
    points.raise_for_status()
    forecast_url = points.json().get("properties", {}).get("forecast")
    if not forecast_url:
        return {"available": False, "periods": [], "alerts": []}

    forecast = requests.get(forecast_url, headers=_HEADERS, timeout=15)
    forecast.raise_for_status()
    periods = forecast.json().get("properties", {}).get("periods", [])

    alerts_resp = requests.get(
        ALERTS_URL,
        headers=_HEADERS,
        params={"point": f"{lat},{lon}", "status": "actual"},
        timeout=15,
    )
    alerts_resp.raise_for_status()
    alerts = alerts_resp.json().get("features", [])

    return {"available": True, "periods": periods, "alerts": alerts}
```

- [ ] **Step 4: Run to verify pass**

Run: `PYTHONPATH=src python tests/test_nws_parsing.py`
Expected: PASS — `All 7 passed`.

- [ ] **Step 5: Commit**

```bash
git add src/kde_weather/backend/api/nws.py tests/test_nws_parsing.py
git commit -m "Add fetch_nws_details NWS client (points -> forecast + alerts)"
```

---

## Task 3: `NwsWorker` background worker

**Files:**
- Modify: `src/kde_weather/backend/api/worker.py`

- [ ] **Step 1: Add the import**

In `src/kde_weather/backend/api/worker.py`, change the existing import line:

```python
from .open_meteo import fetch_forecast, fetch_geocode
```

to also import the NWS client:

```python
from .open_meteo import fetch_forecast, fetch_geocode
from .nws import fetch_nws_details
```

- [ ] **Step 2: Add the `NwsWorker` class**

In the same file, after the `GeocodeWorker` class (before `def run_in_thread`), add:

```python
class NwsWorker(QObject):
    finished = Signal(dict)  # Emits {"available", "periods", "alerts"}
    error = Signal(str)      # Emits the exception message on failure

    def __init__(self, lat, lon):
        super().__init__()
        self._lat = lat
        self._lon = lon

    @Slot()
    def run(self):
        try:
            data = fetch_nws_details(self._lat, self._lon)
            self.finished.emit(data)
        except Exception as e:
            self.error.emit(str(e))
```

- [ ] **Step 3: Verify it imports**

Run: `PYTHONPATH=src python -c "from kde_weather.backend.api.worker import NwsWorker; print('ok')"`
Expected: `ok`.

- [ ] **Step 4: Commit**

```bash
git add src/kde_weather/backend/api/worker.py
git commit -m "Add NwsWorker for off-thread NWS fetches"
```

---

## Task 4: `DayDetail` QObject

**Files:**
- Create: `src/kde_weather/backend/models/day_detail.py`

- [ ] **Step 1: Create the QObject**

Create `src/kde_weather/backend/models/day_detail.py`:

```python
"""QObject exposing the currently-selected day's NWS detail to QML.

What: holds selection + loading/error/availability state and the parsed
      narrative periods and alerts for the day the user clicked.
Why:  QML binds to app.dayDetail.* so the 7-Day detail panel reacts to fetches.
How:  one `changed` signal backs every property; QML re-reads them all whenever
      any mutator fires. Mutators are the only way state changes, keeping each
      transition explicit (select -> loading -> data | unavailable | error).
"""
from PySide6.QtCore import QObject, Signal, Property


class DayDetail(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._selected_date = ""   # "" means collapsed / nothing selected
        self._loading = False
        self._error = ""
        self._available = True
        self._periods = []         # list of {"name", "text"}
        self._alerts = []          # list of {"event","headline","severity","text","expiresText"}

    @Property(str, notify=changed)
    def selectedDate(self):
        return self._selected_date

    @Property(bool, notify=changed)
    def loading(self):
        return self._loading

    @Property(str, notify=changed)
    def error(self):
        return self._error

    @Property(bool, notify=changed)
    def available(self):
        return self._available

    @Property(list, notify=changed)
    def periods(self):
        return self._periods

    @Property(list, notify=changed)
    def alerts(self):
        return self._alerts

    # --- mutators (each emits `changed` exactly once) ---

    def select(self, date_str):
        """Begin showing date_str; reset prior data to a clean pre-load state."""
        self._selected_date = date_str
        self._loading = False
        self._error = ""
        self._available = True
        self._periods = []
        self._alerts = []
        self.changed.emit()

    def clear(self):
        """Collapse the panel (no day selected)."""
        self._selected_date = ""
        self._loading = False
        self._error = ""
        self._available = True
        self._periods = []
        self._alerts = []
        self.changed.emit()

    def set_loading(self):
        self._loading = True
        self._error = ""
        self.changed.emit()

    def set_unavailable(self):
        self._loading = False
        self._available = False
        self._periods = []
        self._alerts = []
        self.changed.emit()

    def set_error(self, msg):
        self._loading = False
        self._error = msg
        self.changed.emit()

    def set_data(self, periods, alerts):
        self._loading = False
        self._error = ""
        self._available = True
        self._periods = periods
        self._alerts = alerts
        self.changed.emit()
```

- [ ] **Step 2: Verify it imports and instantiates (needs a QApplication)**

Run:
```bash
PYTHONPATH=src QT_QPA_PLATFORM=offscreen python -c "
from PySide6.QtWidgets import QApplication
app = QApplication([])
from kde_weather.backend.models.day_detail import DayDetail
d = DayDetail()
d.select('2026-06-17'); assert d.selectedDate == '2026-06-17'
d.set_data([{'name':'Today','text':'Sunny.'}], [])
assert d.periods[0]['name'] == 'Today' and d.loading is False
d.clear(); assert d.selectedDate == ''
print('ok')
"
```
Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add src/kde_weather/backend/models/day_detail.py
git commit -m "Add DayDetail QObject for selected-day NWS state"
```

---

## Task 5: Wire `selectDay` + cache into `AppController`

**Files:**
- Modify: `src/kde_weather/backend/app_controller.py`
- Test: `tests/test_day_detail.py`

- [ ] **Step 1: Write the failing test**

Create `tests/test_day_detail.py`:

```python
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
```

- [ ] **Step 2: Run to verify failure**

Run: `PYTHONPATH=src python tests/test_day_detail.py`
Expected: FAIL — child aborts with `AttributeError: 'AppController' object has no attribute '_nws_cache'` (or `selectDay`), surfaced as `[FAIL] ... (exit 1)`.

- [ ] **Step 3: Add imports to `app_controller.py`**

In `src/kde_weather/backend/app_controller.py`, update the worker import and add two new imports near the other backend imports:

Change:
```python
from .api.worker import ForecastWorker, GeocodeWorker, run_in_thread
```
to:
```python
from .api.worker import ForecastWorker, GeocodeWorker, NwsWorker, run_in_thread
from .api.nws import periods_for_date, alerts_for_date, format_expires
from .models.day_detail import DayDetail
```

- [ ] **Step 4: Initialize `DayDetail` + cache in `__init__`**

In `AppController.__init__`, just after `self._current = CurrentConditions(self)`, add:

```python
        # NWS day-detail state for the 7-Day tab (app.dayDetail), plus a
        # per-location in-memory cache of the (one-shot) NWS fetch result.
        self._day_detail = DayDetail(self)
        self._nws_cache = {}  # keyed by (lat, lon)
```

Then, where the other settings signals are connected (near `self._settings.activeLocationIndexChanged.connect(self.refresh)`), add a line so switching location collapses the panel:

```python
        # Collapse the day-detail panel when the active location changes.
        self._settings.activeLocationIndexChanged.connect(self._day_detail.clear)
```

- [ ] **Step 5: Expose `dayDetail` as a QML property**

After the existing `currentConditions` property (the block ending `return self._current`), add:

```python
    @Property(QObject, constant=True)
    def dayDetail(self):
        return self._day_detail
```

- [ ] **Step 6: Add `selectDay` + helpers**

In the `# --- Actions ---` section (e.g. after `setActiveLocation`), add:

```python
    @Slot(str)
    def selectDay(self, date_str):
        """Expand the NWS detail for a day in the 7-Day tab.

        Clicking the already-open day collapses it. Otherwise we show the day
        and either serve its detail from the per-location cache or kick off a
        single background NWS fetch (the result covers every day).
        """
        if date_str == self._day_detail.selectedDate:
            self._day_detail.clear()
            return

        self._day_detail.select(date_str)
        loc = self._settings.activeLocation
        if loc is None:
            return

        key = (loc["lat"], loc["lon"])
        cached = self._nws_cache.get(key)
        if cached is not None:
            self._populate_detail(date_str, cached)
            return

        self._day_detail.set_loading()
        worker = NwsWorker(loc["lat"], loc["lon"])
        worker.finished.connect(
            lambda payload, k=key, d=date_str: self._on_nws(k, d, payload)
        )
        worker.error.connect(self._on_nws_error)
        self._spawn(worker)

    def _on_nws(self, key, date_str, payload):
        """Cache a completed NWS fetch and populate the panel if still relevant."""
        self._nws_cache[key] = payload
        loc = self._settings.activeLocation
        if loc is None or (loc["lat"], loc["lon"]) != key:
            return  # active location changed while the request was in flight
        if self._day_detail.selectedDate == date_str:
            self._populate_detail(date_str, payload)

    def _on_nws_error(self, msg):
        self._day_detail.set_error(msg)

    def _populate_detail(self, date_str, payload):
        """Fill DayDetail from a cached NWS payload for the given date."""
        if not payload.get("available", False):
            self._day_detail.set_unavailable()
            return

        selected = periods_for_date(payload["periods"], date_str)
        period_list = []
        for period in (selected["day"], selected["night"]):
            if period:
                period_list.append({
                    "name": period.get("name", ""),
                    "text": period.get("detailedForecast", ""),
                })

        alert_list = []
        for props in alerts_for_date(payload["alerts"], date_str):
            end = props.get("expires") or props.get("ends")
            alert_list.append({
                "event": props.get("event", "Alert"),
                "headline": props.get("headline", ""),
                "severity": props.get("severity", "Unknown"),
                "text": props.get("description", ""),
                "expiresText": format_expires(end),
            })

        self._day_detail.set_data(period_list, alert_list)
```

- [ ] **Step 7: Run to verify pass**

Run: `PYTHONPATH=src python tests/test_day_detail.py`
Expected: PASS — `[PASS] selectDay populates dayDetail (exit 0)` then `All 1 passed`.

- [ ] **Step 8: Confirm the earlier thread-shutdown test still passes**

Run: `PYTHONPATH=src python tests/test_thread_shutdown.py`
Expected: PASS — both scenarios.

- [ ] **Step 9: Commit**

```bash
git add src/kde_weather/backend/app_controller.py tests/test_day_detail.py
git commit -m "Wire selectDay + per-location NWS cache into AppController"
```

---

## Task 6: Add `warning` color to the theme

**Files:**
- Modify: `src/kde_weather/qml/theme/Theme.qml`

- [ ] **Step 1: Add the color**

In `src/kde_weather/qml/theme/Theme.qml`, in the "Accent and status" block, after the `error` line, add:

```qml
    readonly property color warning: "#f67400"       // Breeze orange -- moderate alerts
```

- [ ] **Step 2: Commit**

```bash
git add src/kde_weather/qml/theme/Theme.qml
git commit -m "Add Theme.warning color for moderate NWS alerts"
```

---

## Task 7: Make `DayCard` clickable + highlightable

**Files:**
- Modify: `src/kde_weather/qml/components/DayCard.qml`

- [ ] **Step 1: Add `selected`/`clicked` and the highlight border**

In `src/kde_weather/qml/components/DayCard.qml`, in the root `Rectangle` (id `root`), add a selection border and two new members. After the existing `height: 200` line and the existing property block, add the property and signal:

```qml
    // Selection highlight + click handling for the 7-Day detail panel.
    property bool selected: false
    signal clicked()

    border.width: root.selected ? 3 : 0
    border.color: Theme.accent
```

- [ ] **Step 2: Add the MouseArea**

Inside the root `Rectangle`, as the LAST child (after the closing `}` of the `ColumnLayout`, before the `Rectangle`'s closing brace), add:

```qml
    // Full-card click target. Placed last so it sits above the ColumnLayout
    // (whose children have no mouse handlers) and receives the click.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
```

- [ ] **Step 3: Smoke-check QML parses**

Run: `PYTHONPATH=src QT_QPA_PLATFORM=offscreen python -c "
from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine
from pathlib import Path
app = QApplication([])
e = QQmlApplicationEngine()
qml = Path('src/kde_weather/qml')
e.addImportPath(str(qml))
obj = e.loadData(b'import QtQuick\nimport \"components\"\nDayCard { date: \"2026-06-17\"; selected: true }', baseUrl=qml.resolve().as_uri() + '/')
print('ok' if e.rootObjects() else 'FAIL')
"`
Expected: `ok` (no QML error lines printed).

- [ ] **Step 4: Commit**

```bash
git add src/kde_weather/qml/components/DayCard.qml
git commit -m "Make DayCard clickable with a selected highlight"
```

---

## Task 8: `DayDetailPanel` + `DailyView` layout

**Files:**
- Create: `src/kde_weather/qml/components/DayDetailPanel.qml`
- Modify: `src/kde_weather/qml/views/DailyView.qml`

- [ ] **Step 1: Create the panel component**

Create `src/kde_weather/qml/components/DayDetailPanel.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import "../theme"

// Expanded NWS detail for the day selected in the 7-Day tab.
// Reads app.dayDetail (loading / error / available / periods / alerts) and
// renders, top to bottom: the date heading, a transient state line, alert
// boxes (colored by severity), and the day + night narrative paragraphs.
ColumnLayout {
    id: panel
    spacing: Theme.spacingMedium

    // Selected date, e.g. "Wednesday, June 17"
    Text {
        text: {
            var ds = app.dayDetail.selectedDate;
            if (!ds) return "";
            var d = new Date(ds + "T00:00:00");
            var days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
            var months = ["January","February","March","April","May","June",
                          "July","August","September","October","November","December"];
            return days[d.getDay()] + ", " + months[d.getMonth()] + " " + d.getDate();
        }
        font.pixelSize: Theme.fontTitle
        font.bold: true
        color: Theme.text
    }

    // Loading
    Text {
        visible: app.dayDetail.loading
        text: "Loading National Weather Service forecast…"
        font.pixelSize: Theme.fontBody
        color: Theme.textSecondary
    }

    // Non-US / uncovered point
    Text {
        visible: !app.dayDetail.loading && !app.dayDetail.available
        text: "Detailed National Weather Service forecasts are only available for US locations."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        font.pixelSize: Theme.fontBody
        color: Theme.textSecondary
    }

    // Network error (re-click the day to retry)
    Text {
        visible: app.dayDetail.error !== ""
        text: "Couldn't load forecast: " + app.dayDetail.error + "  (click the day again to retry)"
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        font.pixelSize: Theme.fontBody
        color: Theme.error
    }

    // Alerts -- severe/extreme in red, everything else amber
    Repeater {
        model: app.dayDetail.alerts
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            color: Theme.surface
            radius: Theme.radiusMedium
            border.width: 2
            border.color: (modelData.severity === "Severe" || modelData.severity === "Extreme")
                          ? Theme.error : Theme.warning
            implicitHeight: alertCol.implicitHeight + 2 * Theme.spacingMedium

            ColumnLayout {
                id: alertCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Text {
                    text: modelData.event
                          + (modelData.expiresText ? "  —  " + modelData.expiresText : "")
                    font.pixelSize: Theme.fontBody
                    font.bold: true
                    color: (modelData.severity === "Severe" || modelData.severity === "Extreme")
                           ? Theme.error : Theme.warning
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Text {
                    visible: modelData.text !== ""
                    text: modelData.text
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }

    // Day + night narrative paragraphs
    Repeater {
        model: app.dayDetail.periods
        ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: modelData.name
                font.pixelSize: Theme.fontBody
                font.bold: true
                color: Theme.accent
            }
            Text {
                text: modelData.text
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.pixelSize: Theme.fontBody
                color: Theme.text
            }
        }
    }

    // US, available, no alerts and no periods for this (far-out) day
    Text {
        visible: !app.dayDetail.loading && app.dayDetail.available
                 && app.dayDetail.error === ""
                 && app.dayDetail.selectedDate !== ""
                 && app.dayDetail.periods.length === 0
                 && app.dayDetail.alerts.length === 0
        text: "No detailed forecast available for this day."
        font.pixelSize: Theme.fontBody
        color: Theme.textSecondary
    }
}
```

- [ ] **Step 2: Rewrite `DailyView` to a vertical layout**

Replace the entire contents of `src/kde_weather/qml/views/DailyView.qml` with:

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "../components"

// 7-Day forecast: a horizontally-scrollable row of DayCard components, with a
// detail panel below that expands when a day is clicked (NWS narrative + alerts).
// The whole tab scrolls vertically so a long narrative is reachable.
ScrollView {
    id: root
    contentWidth: availableWidth

    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.spacingLarge

        // Horizontally-scrollable row of day cards.
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: row.height
            contentWidth: row.width
            contentHeight: row.height
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            RowLayout {
                id: row
                spacing: Theme.spacingMedium

                Repeater {
                    model: app.dailyModel

                    DayCard {
                        // Role names come from DailyModel.roleNames()
                        date: model.date || ""
                        tempMax: model.tempMax || 0
                        tempMin: model.tempMin || 0
                        precipProb: model.precipProbMax || 0
                        windMax: model.windMax || 0
                        weatherCode: model.weatherCode || 0
                        sunrise: model.sunrise || ""
                        sunset: model.sunset || ""
                        selected: app.dayDetail.selectedDate === (model.date || "")
                        onClicked: app.selectDay(model.date || "")
                    }
                }
            }
        }

        // Expanded NWS detail for the selected day.
        DayDetailPanel {
            Layout.fillWidth: true
            visible: app.dayDetail.selectedDate !== ""
        }
    }
}
```

- [ ] **Step 3: Smoke-check the QML loads**

Run: `PYTHONPATH=src QT_QPA_PLATFORM=offscreen python -c "
from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine
from pathlib import Path
app = QApplication([])
e = QQmlApplicationEngine()
qml = Path('src/kde_weather/qml')
e.addImportPath(str(qml))
data = b'import QtQuick\nimport \"components\"\nDayDetailPanel {}'
e.loadData(data, baseUrl=(qml.resolve().as_uri() + '/'))
print('ok' if e.rootObjects() else 'FAIL')
"`
Expected: `ok` (no QML error output). Note: `app.dayDetail` bindings will warn that `app` is undefined in this isolated load — that's fine; we're only checking the file parses. If parse errors appear, fix them; ignore the `app is not defined` ReferenceError warnings.

- [ ] **Step 4: Commit**

```bash
git add src/kde_weather/qml/components/DayDetailPanel.qml src/kde_weather/qml/views/DailyView.qml
git commit -m "Add DayDetailPanel and expand it below the 7-day row"
```

---

## Task 9: Rebuild package + full verification

**Files:** none (build + manual verification)

- [ ] **Step 1: Run the full test suite**

Run:
```bash
PYTHONPATH=src python tests/test_nws_parsing.py && \
PYTHONPATH=src python tests/test_day_detail.py && \
PYTHONPATH=src python tests/test_thread_shutdown.py
```
Expected: all three print their pass lines and exit 0.

- [ ] **Step 2: Rebuild and reinstall the Arch package**

Run:
```bash
cd packaging && makepkg -f --noconfirm && \
sudo pacman -U --noconfirm "$(ls kde-weather-*.pkg.tar.*)" && cd ..
```
Expected: `installing kde-weather...` with no errors. (The new `nws.py`, `day_detail.py`, and the two new QML files must appear in the wheel — they're covered by the existing `packages.find` and the `qml/**` package-data globs.)

- [ ] **Step 3: Confirm new files shipped in the package**

Run: `pacman -Ql kde-weather | grep -E "nws.py|day_detail.py|DayDetailPanel.qml"`
Expected: three matching lines under `/usr/lib/.../site-packages/` and `.../qml/components/`.

- [ ] **Step 4: Manual verification (real app, US location)**

Run: `kde-weather`
Then:
1. Go to the **7-Day** tab.
2. Click a day card → it gets a blue highlight border and a panel expands below with the **daytime** and **nighttime** NWS narrative paragraphs (and any active alerts in a colored box).
3. Click the **same** day again → the panel collapses.
4. Add/switch to a **non-US** location (e.g. search "Paris"), open the 7-Day tab, click a day → the panel shows the "only available for US locations" notice.
5. Close the app from the window button → it exits cleanly (no core dump; the earlier shutdown fix still applies to the new `NwsWorker`).

Expected: all five behaviors as described.

- [ ] **Step 5: Final commit (if any manual-fix tweaks were needed)**

```bash
git add -A
git commit -m "Polish NWS day-detail after manual verification"
```
(Skip if Steps 1–4 needed no changes.)

---

## Self-Review Notes

- **Spec coverage:** data source/module (Tasks 1–2), threading+cache (Tasks 3, 5), backend→QML surface (Tasks 4–5), UI panel + clickable card + non-US/error/no-data states (Tasks 6–8), tests (Tasks 1, 2, 5), manual verification (Task 9). All spec sections map to tasks.
- **Type consistency:** `DayDetail` mutators (`select`, `set_loading`, `set_unavailable`, `set_error`, `set_data`, `clear`) and properties (`selectedDate`, `loading`, `error`, `available`, `periods`, `alerts`) are used identically in Task 5. `_nws_cache` keyed by `(lat, lon)`. Alert dict keys (`event`, `severity`, `text`, `expiresText`) produced in Task 5 match those read in Task 8. Period dict keys (`name`, `text`) match. `fetch_nws_details` return shape (`available`/`periods`/`alerts`) is consistent across Tasks 2, 3, 5.
- **No placeholders:** every code step contains complete code; every run step has an exact command and expected output.
```
