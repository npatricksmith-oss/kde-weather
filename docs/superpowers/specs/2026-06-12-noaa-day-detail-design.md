# NOAA/NWS Day Detail — Design

**Date:** 2026-06-12
**Status:** Approved (pending spec review)

## Summary

In the 7-Day forecast tab, clicking a day expands a panel below the day row
showing the US National Weather Service (NWS / NOAA) narrative for that day —
the daytime and nighttime forecast paragraphs — plus any hazardous/emergency
alerts (watches, warnings, advisories) active on that day.

The existing forecast comes from Open-Meteo, which does not provide narrative
text or US alerts. This feature adds a second data source: the National Weather
Service API (`api.weather.gov`), which is free, keyless, and US-only.

## Goals

- Clicking a day card expands a readable narrative paragraph below the row.
- Show NWS daytime **and** nighttime narratives for the selected date.
- Surface hazardous/emergency alerts active on the selected date, prominently.
- Degrade gracefully for non-US (uncovered) locations with a clear notice.
- Reuse the app's existing worker-thread + model patterns; no UI freezes.

## Non-Goals (YAGNI)

- No persistent on-disk cache (session/in-memory cache only).
- No auto-refresh of narratives on the refresh timer.
- No per-severity icon set — two color tiers only.
- No change to the existing Open-Meteo data flow or the Hourly tab.

## Decisions (from brainstorming)

| Decision | Choice |
|----------|--------|
| Fetch timing | On first day-click, cached per location for the session |
| Periods shown | Daytime **and** nighttime narratives |
| Non-US locations | Clicking still expands; shows a friendly "US-only" notice |
| Alert scope | Alerts whose effective–expires window overlaps the clicked date |

## Data Source: NWS API

US-only, no API key, but **requires a `User-Agent` header** identifying the app
(NWS returns 403 without one). The flow is three HTTP requests:

1. `GET https://api.weather.gov/points/{lat},{lon}`
   → `properties.forecast` (the forecast URL). A 404 or missing forecast URL
   means the point is not covered → treat as "not available" (not an error).
2. `GET {properties.forecast}`
   → `properties.periods[]`, each with:
   - `name` — e.g. "Wednesday", "Wednesday Night", "This Afternoon", "Tonight"
   - `startTime` — ISO 8601 with local offset
   - `isDaytime` — bool
   - `detailedForecast` — the narrative paragraph
3. `GET https://api.weather.gov/alerts/active?point={lat},{lon}`
   → `features[].properties`, each with `event`, `headline`, `severity`
   (Extreme/Severe/Moderate/Minor/Unknown), `effective`, `expires`,
   `description`, `instruction`.

NWS provides roughly 7 days of periods; far-out Open-Meteo days may have no
matching NWS period → the panel shows "No detailed forecast available for this
day."

## Architecture

```
DayCard (clicked, date) ── DailyView ──> app.selectDay(date)
                                              │
                                   AppController.selectDay()
                                    │            │
                          cache hit │            │ cache miss
                                    │            ▼
                                    │     NwsWorker on QThread (_spawn/_active)
                                    │            │  fetch_nws_details(lat, lon)
                                    │            ▼
                                    └──> populate app.dayDetail (DayDetail QObject)
                                                 │
                                          QML panel reacts via property bindings
```

### New module: `backend/api/nws.py`

- `NWS_USER_AGENT` constant (app name + repo URL for NWS contact requirement).
- `fetch_nws_details(lat, lon) -> dict` — performs the three requests and returns
  `{"available": bool, "periods": list, "alerts": list}`. Network/HTTP errors
  other than an uncovered-point 404 propagate as exceptions (worker turns them
  into an error state). An uncovered point returns `{"available": False, ...}`.
- Pure helpers (no network, unit-tested):
  - `periods_for_date(periods, date_str) -> dict` returning
    `{"day": {...}|None, "night": {...}|None}`. Grouping is by the local date of
    each period's `startTime`; the daytime period is `isDaytime=True`, the
    nighttime period `isDaytime=False`.
  - `alerts_for_date(alerts, date_str) -> list` — alerts whose
    `[effective, expires]` (falling back to `onset`/`ends`) window overlaps the
    local day `[date 00:00, date+1 00:00)`.

### Worker: `backend/api/worker.py`

- `NwsWorker(QObject)` with `finished = Signal(dict)` / `error = Signal(str)`,
  mirroring `ForecastWorker`. Its `run()` calls `fetch_nws_details`.
- Spawned via the existing `AppController._spawn()` so it uses the `_active`
  tracking and clean shutdown added previously.

### Backend coordinator: `backend/app_controller.py`

- New `DayDetail` QObject (its own module `backend/models/day_detail.py`),
  owned by `AppController`, exposed to QML as `app.dayDetail`. Notify-backed
  properties:
  - `selectedDate: str` (empty = nothing selected / collapsed)
  - `loading: bool`
  - `error: str`
  - `available: bool`
  - `periods: list` of `{"name": str, "text": str}` (day then night)
  - `alerts: list` of
    `{"event", "headline", "severity", "text", "expiresText"}`
- `AppController`:
  - `@Slot(str) selectDay(date_str)`:
    - If `date_str` equals the current `selectedDate`, collapse (clear selection)
      and return — this gives click-to-toggle.
    - Set `selectedDate`. If NWS data for the active location is cached, populate
      `dayDetail` immediately. Otherwise set `loading=true` and `_spawn` an
      `NwsWorker`; on `finished`, cache the result keyed by the active location
      and populate `dayDetail` for the still-selected date; on `error`, set the
      error state.
  - In-memory cache: `self._nws_cache` keyed by `(lat, lon)`. Cleared whenever
    the active location changes (hook into the existing `refresh()` /
    `activeLocationIndexChanged` path), which also collapses the panel.
  - Populating `dayDetail` from cache uses `periods_for_date` /
    `alerts_for_date`. `available` comes from the cached payload.

### UI: QML

- `components/DayCard.qml`:
  - Add `signal clicked()` and a `MouseArea` (full-card) that emits it.
  - Add `property bool selected` → highlighted border (Theme highlight color)
    when true.
- `views/DailyView.qml`:
  - Restructure from a single horizontal `ScrollView` into a **vertical** scroll
    containing:
    1. The existing horizontally-scrollable day row (`Repeater` of `DayCard`).
       Wire `DayCard.onClicked: app.selectDay(model.date)` and
       `selected: app.dayDetail.selectedDate === model.date`.
    2. A **detail panel** below, visible when `app.dayDetail.selectedDate !== ""`.
       Top to bottom:
       - Selected-day heading (formatted date).
       - `loading` → "Loading…" line.
       - `available === false` → "Detailed National Weather Service forecasts
         are only available for US locations." notice.
       - `error` non-empty → error line; clicking the day again retries.
       - Alerts `Repeater` — each alert in a rounded box colored by severity
         (Severe/Extreme → red, else amber), showing the event name (bold),
         expiry text, and the alert text.
       - Day narrative, then night narrative (each: period name bold + paragraph,
         text wrapped). If both periods are missing → "No detailed forecast
         available for this day."
- `theme/Theme.qml`: add two alert colors (`alertSevere`, `alertModerate`) if
  not already expressible with existing tokens.

## Error Handling

- Uncovered point (non-US): `available=false`, friendly notice. Not an error.
- Network/HTTP failure: worker emits `error`; panel shows an error line.
  Re-clicking the day clears the error and refetches.
- Missing NWS period for a valid US date: "No detailed forecast available."
- Worker lifecycle: reuses `_spawn`/`_active`/`shutdown()` — no teardown crash.

## Testing

- `tests/test_nws_parsing.py` (standalone, no framework — matches the existing
  `tests/test_thread_shutdown.py` style). Feeds sample NWS JSON fixtures to the
  pure helpers and asserts:
  - `periods_for_date` selects the correct day/night period for a date and
    returns `None` for a date with no period.
  - `alerts_for_date` includes an alert overlapping the date and excludes one
    outside the window (boundary cases at local midnight).
- Manual verification: run the app, click a day for the saved US location
  ("Mexico, New York"), confirm the day+night narrative appears; confirm the
  US-only notice for a non-US location; confirm click-again collapses.

## Files Touched

| File | Change |
|------|--------|
| `backend/api/nws.py` | New — NWS HTTP client + pure parsing helpers |
| `backend/api/worker.py` | Add `NwsWorker` |
| `backend/models/day_detail.py` | New — `DayDetail` QObject |
| `backend/app_controller.py` | `selectDay()`, NWS cache, own `DayDetail` |
| `qml/components/DayCard.qml` | Click signal + `selected` highlight |
| `qml/views/DailyView.qml` | Vertical layout + detail panel |
| `qml/theme/Theme.qml` | Alert severity colors (if needed) |
| `tests/test_nws_parsing.py` | New — pure-helper tests |
