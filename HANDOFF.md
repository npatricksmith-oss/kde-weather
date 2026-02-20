# KDE Weather - Session Handoff

## What This Is

A standalone Qt weather app for KDE Plasma. Displays hourly charts and daily forecast cards using data from the Open-Meteo API (free, no key). Dark theme UI matching Breeze Dark.

## Current State

**Working and verified:**
- App launches, dark theme displays correctly
- Location search via geocoding autocomplete
- Manual lat/lon entry
- Multiple saved locations with switching
- Settings persistence to `~/.config/kde-weather/settings.json`
- API calls run on background QThreads (non-blocking UI)
- 7-Day forecast tab with DayCard components
- Auto-refresh timer (15/30/60 min configurable)
- Current conditions header bar with live day/date/time (updates every minute)
- 48-hour hourly charts with real timestamps on x-axis (DateTimeAxis)
- Charts start at the current hour and run 48 hours forward
- X-axis shows day + time labels ("Wed 9 PM", "Thu 3 AM", etc.), one tick per ~6 hours
- Y-axis snaps to clean intervals (10°F steps for temp, 10% for humidity, etc.)
- Wind speed y-axis floored at 0 (never shows negative)
- Weather icons have a contrast background circle (visible on dark surfaces)
- install.sh uses the project venv (not pip --user), creates ~/.local/bin/kde-weather wrapper and installs .desktop file

**Not yet implemented (from issue-tracker.md):**
- A3: Alternating date shading bands inside chart area
- B2: Daily forecast icon reflects dominant weather for the day (currently uses daily weather_code which may be the last hour's code)
- B3: Click a day card to expand a written forecast description below
- B4: Snow-day probability shown in icon area when > 10%
- General 1: Help page (appears when a help icon is clicked, top right)
- General 2: API rate limit documentation + refresh interval options adjusted accordingly
- General 4: Hazardous weather / NWS advisories button (requires a separate API — Open-Meteo does not provide alerts)

## Tech Stack

| Component | Choice | Why |
|---|---|---|
| UI framework | PySide6 + QML | Qt-native for KDE, QML for declarative UI |
| Charts | QtCharts (SplineSeries + DateTimeAxis) | Smooth curves, real timestamp x-axis, built into Qt |
| API | Open-Meteo | Free, no API key, WMO data source |
| HTTP | `requests` library | Simple, synchronous (run in QThread workers) |
| Widget style | Fusion + manual palette | Fusion accepts custom palettes; native Breeze style overrides them |
| Settings | Plain JSON file | No dependency on KConfig, portable |

## Architecture

```
main.py                         Entry point, QApplication + QML engine setup
  |
  v
AppController (QObject)         Central coordinator, exposed to QML as "app"
  |-- Settings                  JSON config read/write with Q_PROPERTY bindings
  |-- HourlyModel               QAbstractListModel, 48-hr data + seriesData() for charts
  |-- DailyModel                QAbstractListModel, 7-day data
  |-- LocationModel             Mirror of Settings.locations for QML ComboBox
  |-- GeocodeModel              Search results for autocomplete dropdown
  |-- CurrentConditions         QObject with current weather properties (from current hour)
  |-- ForecastWorker (QThread)  Background HTTP call for forecast
  |-- GeocodeWorker (QThread)   Background HTTP call for city search
```

### Data flow

1. User action or timer triggers `AppController.refresh()`
2. `ForecastWorker` spawned on `QThread`, calls Open-Meteo API
3. Worker emits `finished(dict)` signal (cross-thread, auto-queued by Qt)
4. `_on_forecast()` updates HourlyModel, DailyModel, CurrentConditions
5. HourlyModel finds `start_idx` (first API hour >= current local time), stores 48 rows from there
6. HourlyModel bumps `dataVersion` property
7. QML's `onDataVersionChanged` calls `refreshCharts()` which pushes data to charts
8. WeatherChart's `onSeriesDataChanged` calls `updateChart()` which redraws SplineSeries

### Key design pattern: `dataVersion`

QML can't detect when a Python Slot method would return different results — declarative bindings only react to Q_PROPERTY notify signals. The `dataVersion` pattern bridges this:

- Python model increments `dataVersion` (int property with signal) after data changes
- QML binds to `dataVersion` and uses `onDataVersionChanged` to imperatively re-call Slot methods
- This avoids the need to make every data series a separate Q_PROPERTY

### Key design pattern: `start_idx`

Open-Meteo returns hourly data from local midnight. `HourlyModel.update()` scans forward to find the first time slot >= current hour and stores that as `start_idx`. The hourly chart rows start there. `AppController` also passes `start_idx` to `CurrentConditions.update_from_hourly()` so the banner shows the actual current hour's conditions, not midnight's.

### Key design pattern: `clampMin` on WeatherChart

`WeatherChart` exposes a `clampMin` property (default `-1e9`, effectively disabled). When set to `0`, the y-axis floor is prevented from going negative. Used on all wind charts. Implemented via `axisMin = Math.max(axisMin, root.clampMin)` in `updateChart()`.

## Bugs Fixed During Development

### 1. PySide6 shutdown crash (segfault on exit)
**Fix:** Explicit `del engine; del controller; del app` in correct order in `main.py`.

### 2. Worker thread GC (API calls silently failing)
**Fix:** `AppController` stores both `_forecast_thread` AND `_forecast_worker` as instance attributes to prevent GC.

### 3. Charts not reacting to data updates
**Fix:** `dataVersion` property pattern — QML's `onDataVersionChanged` imperatively pushes fresh data to each chart.

### 4. X-axis showing fractional hour indices (0.0 … 47.0)
**Fix:** `seriesData()` now returns Unix ms timestamps as x values. QML uses `DateTimeAxis` instead of `ValuesAxis`, format `"ddd h AP"`.

### 5. Charts showing historical data from midnight instead of starting at current time
**Fix:** `HourlyModel.update()` computes `start_idx` (first hour >= now) and slices from there. Both the chart data and `CurrentConditions` now use this index.

### 6. install.sh failing with externally-managed-environment error
**Fix:** `install.sh` now creates/reuses `.venv` with `--system-site-packages`, installs via venv pip, and writes a wrapper script to `~/.local/bin/kde-weather` so the `.desktop` file's `Exec=kde-weather` resolves correctly.

### 7. Scrolling charts covering header and tab bar
**Fix:** Removed nested `Flickable` inside `ScrollView` in `HourlyView.qml`. `ColumnLayout` is now a direct child of `ScrollView` (correct QQC2 pattern).

### 8. Wind speed y-axis going negative
**Fix:** `clampMin: 0` on wind charts. Y-axis floor is clamped at 0.

## File Map

```
src/kde_weather/
  main.py                           App entry point
  backend/
    app_controller.py               Central QObject exposed to QML as "app"
    settings.py                     JSON settings at ~/.config/kde-weather/
    api/
      open_meteo.py                 HTTP client (forecast + geocoding)
      worker.py                     QThread workers for async API calls
    models/
      hourly_model.py               48-hr data model + chart series provider
                                    (start_idx: first hour >= now)
      daily_model.py                7-day summary model
      location_model.py             Saved locations model (mirrors Settings)
      geocode_model.py              City search results model
      current_conditions.py         Current weather snapshot (uses start_idx)
  qml/
    main.qml                        Root window, toolbar, tabs, settings drawer
    theme/
      Theme.qml                     Breeze Dark color/spacing constants (singleton)
      qmldir                        QML module declaration for singleton
    views/
      HourlyView.qml                ScrollView > ColumnLayout of WeatherChart panels
      DailyView.qml                 Horizontal row of DayCard components
      SettingsView.qml              Location mgmt + element toggles + refresh interval
    components/
      CurrentConditions.qml         Top bar: temp, wind, humidity + live day/date/time
      WeatherChart.qml              ChartView with DateTimeAxis, nice Y intervals, clampMin
      DayCard.qml                   Single day forecast card
      LocationSearchBar.qml         Debounced city search with autocomplete
      WeatherIcon.qml               WMO code -> emoji with contrast background circle
```

## How to Run

```bash
# First-time setup (creates venv, installs desktop entry):
bash ~/1_Projects/Software/kde-weather/install.sh

# Daily use (terminal):
kde-weather

# Or directly via venv (no install required):
cd ~/1_Projects/Software/kde-weather
.venv/bin/kde-weather
```

**System packages required:** `pyside6 qt6-charts python-requests` (via pacman)

## Open Items from Issue Tracker

### A3 — Date shading bands on charts
Alternating background rectangles inside each `ChartView` for each calendar day. Requires calculating pixel coordinates of midnight transitions from the `DateTimeAxis` range — doable but needs QtCharts internals (`ChartView.mapToPosition()`).

### B2 — Daily forecast icon reflects dominant weather
The daily model already receives `weather_code` from Open-Meteo's daily summary endpoint, which should represent the dominant condition. Worth verifying the API returns the right code vs the last-hour code.

### B3 — Click day card to expand written forecast
Add a `MouseArea` to `DayCard`, emit a signal with the date/weather-code, and show a description panel in `DailyView`. The `WMO_DESCRIPTIONS` dict already exists in `current_conditions.py` — expose it or duplicate to QML.

### B4 — Snow-day probability
Heuristic: combine `snowfall_sum` and `precipitation_probability` for the day. Show a small label (e.g., "❄ Snow day?") in the icon area of `DayCard` when a threshold is crossed.

### General 1 — Help page
Add a `?` `ToolButton` in the main toolbar that opens a `Dialog` or second `Drawer` with usage info, keyboard shortcuts, API credit.

### General 2 — API usage / refresh intervals
Open-Meteo is free and has no hard rate limit for reasonable usage (their docs suggest ≤10,000 calls/day for free tier). The current refresh options (15/30/60 min) are appropriate. Minimum sensible interval is 15 min since forecasts don't update more frequently. No changes needed — just document this in the help page.

### General 4 — Hazardous weather / NWS advisories
Open-Meteo does not provide weather alerts. The NWS Alerts API (`https://api.weather.gov/alerts/active`) is free for US locations, no key required. Would need a new API module + worker + UI surface (e.g., a banner or dialog).

## Future API Considerations

### Open-Meteo vs NWS (weather.gov) — decision rationale

**Open-Meteo remains the primary API** because it's free, needs no API key, has global coverage, and returns flat JSON in a single request. NWS is US-only and requires a multi-step lookup (lat/lon → `/points` → grid office → `/forecast`), which adds complexity for no benefit outside the US.

**NWS is worth adding selectively** for two features it uniquely provides:
- **Hazardous weather alerts** — `GET /alerts/active?point={lat},{lon}` is the best free source for US weather warnings. No other free API matches it.
- **Written forecast text** — NWS `/forecast` returns human-readable period descriptions ("Partly cloudy with a chance of showers...") that Open-Meteo doesn't offer. Useful for the B3 expandable day card feature.

**Implementation approach:** Detect US locations and layer NWS data on top of Open-Meteo when available. Non-US locations fall back to Open-Meteo-only.

### Radar map — RainViewer API

**RainViewer (`https://www.rainviewer.com/api.html`)** is the best fit for adding a radar map:
- Free, no API key, no registration — matches the project's no-key design
- Global coverage (composites from radar networks worldwide)
- Standard slippy map tiles (`/z/x/y.png`) that overlay on any tile-based map
- Provides past radar frames + short-term nowcast (1-2 hrs ahead)
- Simple API: one call to get available frame timestamps, then tile URLs are templated

**QML implementation notes:**
- PySide6's `QtLocation` module can render slippy maps with tile overlays
- Use `Map` item with OpenStreetMap as the base layer
- Add a custom tile overlay for RainViewer radar frames
- Animate through past frames for the radar loop effect
- **Prototype the QtLocation tile overlay early** — getting custom tile sources working in QML with PySide6 is the trickiest part, not the API integration itself
