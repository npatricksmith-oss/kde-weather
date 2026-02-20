# CLAUDE.md

- This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
- Always comment your code, usefully commenting 1. what you did, 2. what it does, 3. Why you did it that way.
  
## Project Overview

KDE Plasma weather app using PySide6 + QML with data from the free Open-Meteo API (no API key required). Targets Arch Linux with system-level Qt packages.

## Commands

```bash
# First-time setup (installs system packages via pacman, creates .venv, installs desktop entry)
bash install.sh

# Run (after installation)
kde-weather

# Run directly from venv (development, no install needed)
.venv/bin/kde-weather

# Development install (editable mode, run from project root)
pip install -e .
```

No test suite exists — testing is manual by running the app.

## Architecture

**Pattern:** MVC with Python backend and QML frontend.

```
main.py (QApplication + QML engine)
  └── AppController (QObject, exposed to QML as "app")
        ├── Settings        → ~/.config/kde-weather/settings.json
        ├── HourlyModel     → 48-hour forecast (QAbstractListModel)
        ├── DailyModel      → 7-day forecast (QAbstractListModel)
        ├── LocationModel   → Saved locations (for ComboBox)
        ├── GeocodeModel    → City search results
        ├── CurrentConditions → Current weather snapshot
        ├── ForecastWorker  → Background QThread (Open-Meteo API)
        └── GeocodeWorker   → Background QThread (Geocoding API)
```

**Data flow:** User action/timer → Worker spawned on QThread → HTTP request (blocking, off main thread) → Signal emitted → Main thread callback updates models → QML reacts via property bindings.

## Critical Patterns

### dataVersion Pattern
QML declarative bindings can't detect when a Python `@Slot` method returns different data. The fix: Python models expose an `int dataVersion` property that increments after each update. QML binds to it and calls imperative refresh methods in `onDataVersionChanged`.

### start_idx Pattern
Open-Meteo returns hourly data from local midnight. `HourlyModel.update()` scans forward to find the first hour ≥ current hour and stores it as `start_idx`. Charts and `CurrentConditions` use this offset so "now" appears at the left edge, not midnight.

### Worker Thread Safety
Both the thread and worker objects must be stored as instance attributes on `AppController`. If only the thread is retained, Python's GC destroys the worker while the HTTP request is in-flight, causing a segfault when the worker tries to emit a signal.

```python
# Correct — store BOTH refs
self._forecast_thread, self._forecast_worker = run_in_thread(worker)
```

### Why Fusion Style (not Breeze)
PySide6's `Fusion` style accepts custom QPalettes; the `Breeze` style ignores them. All Breeze Dark colors are applied manually via `QPalette` in `main.py` to guarantee correct appearance outside KDE.

## Key Files

| File | Role |
|------|------|
| `src/kde_weather/main.py` | QApplication setup, Fusion + Breeze Dark palette, QML engine init |
| `src/kde_weather/backend/app_controller.py` | Central coordinator; all models, workers, and settings owned here |
| `src/kde_weather/backend/api/worker.py` | `run_in_thread()` helper and Worker base pattern |
| `src/kde_weather/backend/api/open_meteo.py` | HTTP calls to Open-Meteo Forecast and Geocoding endpoints |
| `src/kde_weather/backend/models/hourly_model.py` | `seriesData()` Slot returns chart-ready arrays; handles `start_idx` |
| `src/kde_weather/qml/main.qml` | Root window; toolbar, tabs, settings drawer |
| `src/kde_weather/qml/components/WeatherChart.qml` | Reusable `ChartView` with `DateTimeAxis` and smart Y-axis intervals |
| `src/kde_weather/qml/theme/Theme.qml` | Breeze Dark color/spacing singleton; used throughout QML |

## Arch Linux Specifics

- Qt6/PySide6 is installed system-wide via pacman; the venv is created with `--system-site-packages` so it can see Qt without duplicating the large install.
- System packages required: `pyside6 qt6-charts python-requests`
- The install script creates a wrapper at `~/.local/bin/kde-weather` that activates the venv before running.

## Issue Tracking

See `issues.md` for the full backlog of open issues and feature requests.
