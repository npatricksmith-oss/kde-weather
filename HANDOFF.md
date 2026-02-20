# KDE Weather - Session Handoff

## What This Is

A standalone Qt weather app for KDE Plasma.  Displays hourly charts and daily forecast cards using data from the Open-Meteo API (free, no key).  Dark theme UI matching Breeze Dark.

## Current State

**Working:**
- App launches, dark theme displays correctly
- Location search via geocoding autocomplete
- Manual lat/lon entry
- Multiple saved locations with switching
- Settings persistence to `~/.config/kde-weather/settings.json`
- API calls run on background QThreads (non-blocking UI)
- 7-Day forecast tab with DayCard components
- Auto-refresh timer (15/30/60 min configurable)
- Current conditions header bar

**Not yet verified working (needs testing):**
- 48-hour hourly chart data population (the `dataVersion` reactivity fix was applied but not visually confirmed)
- Weather element toggle checkboxes actually hiding/showing charts
- Chart rendering quality and axis labels

## Tech Stack

| Component | Choice | Why |
|---|---|---|
| UI framework | PySide6 + QML | Qt-native for KDE, QML for declarative UI |
| Charts | QtCharts (SplineSeries) | Smooth curves, built into Qt, no extra deps |
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
  |-- LocationModel              Mirror of Settings.locations for QML ComboBox
  |-- GeocodeModel               Search results for autocomplete dropdown
  |-- CurrentConditions          QObject with current weather properties (from hourly[0])
  |-- ForecastWorker (QThread)   Background HTTP call for forecast
  |-- GeocodeWorker (QThread)    Background HTTP call for city search
```

### Data flow

1. User action or timer triggers `AppController.refresh()`
2. `ForecastWorker` spawned on `QThread`, calls Open-Meteo API
3. Worker emits `finished(dict)` signal (cross-thread, auto-queued by Qt)
4. `_on_forecast()` updates HourlyModel, DailyModel, CurrentConditions
5. HourlyModel bumps `dataVersion` property
6. QML's `onDataVersionChanged` calls `refreshCharts()` which pushes data to charts
7. WeatherChart's `onSeriesDataChanged` calls `updateChart()` which redraws SplineSeries

### Key design pattern: `dataVersion`

QML can't detect when a Python Slot method would return different results -- declarative bindings only react to Q_PROPERTY notify signals.  The `dataVersion` pattern bridges this:

- Python model increments `dataVersion` (int property with signal) after data changes
- QML binds to `dataVersion` and uses `onDataVersionChanged` to imperatively re-call Slot methods
- This avoids the need to make every data series a separate Q_PROPERTY

## Bugs Fixed During Development

### 1. PySide6 shutdown crash (segfault on exit)

**Problem:** Python's GC destroyed Qt objects in wrong order during process exit, causing segfault.
**Fix:** Explicit `del engine; del controller; del app` in correct order in `main.py`.

### 2. Worker thread GC (API calls silently failing)

**Problem:** `ForecastWorker` was created as a local variable, moved to a QThread, but Python GC'd it before the HTTP request finished because nothing held a reference.  The API call would never complete and data would stay at zero.
**Fix:** `AppController` stores both `_forecast_thread` AND `_forecast_worker` as instance attributes to prevent GC.

### 3. Charts not reacting to data updates

**Problem:** QML bindings like `seriesData: hourlyModel.seriesData("temperature")` are evaluated once at creation -- QML has no way to know the Slot would return different data after a model reset.
**Fix:** Added `dataVersion` property pattern (see above).  `onDataVersionChanged` imperatively pushes fresh data to each chart.

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
      daily_model.py                7-day summary model
      location_model.py             Saved locations model (mirrors Settings)
      geocode_model.py              City search results model
      current_conditions.py         Current weather snapshot (from hourly[0])
  qml/
    main.qml                        Root window, toolbar, tabs, settings drawer
    theme/
      Theme.qml                     Breeze Dark color/spacing constants (singleton)
      qmldir                        QML module declaration for singleton
    views/
      HourlyView.qml                Stacked charts, visibility-gated by settings
      DailyView.qml                 Horizontal row of DayCard components
      SettingsView.qml              Location mgmt + element toggles + refresh interval
    components/
      CurrentConditions.qml         Top summary bar (temp, wind, humidity, etc.)
      WeatherChart.qml              Reusable ChartView + SplineSeries panel
      DayCard.qml                   Single day forecast card
      LocationSearchBar.qml         Debounced city search with autocomplete
      WeatherIcon.qml               WMO code -> emoji mapper
```

## How to Run

```bash
cd ~/1_Projects/Software/kde-weather
.venv/bin/kde-weather
```

Or if the venv isn't set up:

```bash
python -m venv --system-site-packages .venv
.venv/bin/pip install -e .
.venv/bin/kde-weather
```

**System packages required:** `pyside6 qt6-charts python-requests` (via pacman)

## What to Work On Next

### Priority 1: Verify and fix chart rendering
- Confirm charts actually display data after the dataVersion fix
- Check that x-axis labels show readable times (currently shows hour indices 0-47)
- Test toggling weather elements on/off in settings

### Priority 2: UI polish
- X-axis time labels on charts (currently numeric indices, should show "2pm", "8am", etc.)
- Loading spinner styling (may use default Qt style, not Breeze-themed)
- Error toast/banner instead of small text in toolbar
- Chart area fill (subtle gradient under the spline for visual weight)
- Wind direction indicator (compass arrows or degrees label)

### Priority 3: Features
- Response caching (don't re-fetch if last fetch was < 5 min ago)
- Celsius/metric unit toggle
- Keyboard shortcut for refresh (F5 or Ctrl+R)
- System tray integration
- `.desktop` file installation via install.sh (file exists but install.sh needs testing)

### Priority 4: Code quality
- Git init + initial commit
- Add `__main__.py` so `python -m kde_weather` works
- Error handling for network-down state (currently shows raw exception text)
- Test with multiple locations to verify switching works cleanly
