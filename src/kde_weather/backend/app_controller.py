"""
Central controller that wires together settings, API workers, and data models.

Exposed to QML as the "app" context property.  QML accesses everything
through this object:
  - app.settings         (Settings QObject)
  - app.hourlyModel      (HourlyModel)
  - app.dailyModel       (DailyModel)
  - app.locationModel    (LocationModel)
  - app.geocodeModel     (GeocodeModel)
  - app.currentConditions (CurrentConditions)
  - app.refresh()        (trigger forecast fetch)
  - app.searchCity(q)    (trigger geocode search)
  - app.loading / app.error / app.lastUpdate (UI state)

Data flow:
  1. User triggers refresh (button, timer, or location change)
  2. refresh() spawns a ForecastWorker on a background QThread
  3. Worker calls Open-Meteo API (blocking HTTP, but off main thread)
  4. Worker emits finished(dict) which is delivered to main thread
     via Qt's queued connection (automatic for cross-thread signals)
  5. _on_forecast() updates all three data models
  6. QML reacts to model signals and repaints
"""

from datetime import datetime

from PySide6.QtCore import QObject, QTimer, Signal, Slot, Property

from .settings import Settings
from .api.worker import ForecastWorker, GeocodeWorker, NwsWorker, run_in_thread
from .api.nws import periods_for_date, alerts_for_date, format_expires
from .models.day_detail import DayDetail
from .models.hourly_model import HourlyModel
from .models.daily_model import DailyModel
from .models.location_model import LocationModel
from .models.geocode_model import GeocodeModel
from .models.current_conditions import CurrentConditions


class AppController(QObject):
    loadingChanged = Signal()
    errorChanged = Signal()
    lastUpdateChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)

        self._settings = Settings(self)
        self._hourly_model = HourlyModel(self)
        self._daily_model = DailyModel(self)
        self._location_model = LocationModel(self)
        self._geocode_model = GeocodeModel(self)
        self._current = CurrentConditions(self)

        # NWS day-detail state for the 7-Day tab (app.dayDetail), plus a
        # per-location in-memory cache of the (one-shot) NWS fetch result.
        self._day_detail = DayDetail(self)
        self._nws_cache = {}  # keyed by (lat, lon)

        self._loading = False
        self._error = ""
        self._last_update = ""

        # Every in-flight (thread, worker) pair lives here.  We must hold
        # references to BOTH until the thread has fully stopped, or Python's GC
        # destroys a running QThread -> qFatal -> SIGABRT.  Using a list (not a
        # single attribute per kind) means a rapid second refresh can't drop the
        # first request's thread while it is still running -- each pair is
        # removed only by _reap(), after its thread emits finished().
        self._active = []

        # Auto-refresh timer -- restarts whenever the interval changes
        self._refresh_timer = QTimer(self)
        self._refresh_timer.timeout.connect(self.refresh)
        self._update_timer_interval()

        # React to settings changes
        self._settings.refreshIntervalChanged.connect(self._update_timer_interval)
        self._settings.locationsChanged.connect(self._sync_location_model)
        self._settings.activeLocationIndexChanged.connect(self.refresh)
        # Collapse the day-detail panel when the active location changes.
        self._settings.activeLocationIndexChanged.connect(self._day_detail.clear)

        # Initialize location model from saved settings
        self._sync_location_model()

        # If a location was saved from a previous session, fetch data now
        if self._settings.activeLocation is not None:
            self.refresh()

    def _update_timer_interval(self):
        mins = self._settings.refreshIntervalMinutes
        self._refresh_timer.start(mins * 60 * 1000)

    def _sync_location_model(self):
        """Push the settings location list into the QML-facing model."""
        self._location_model.update(self._settings.locations)

    # --- Properties exposed to QML ---
    # These are constant=True because the model *objects* never change --
    # only their contents do (via internal signals like modelReset).

    @Property(QObject, constant=True)
    def settings(self):
        return self._settings

    @Property(QObject, constant=True)
    def hourlyModel(self):
        return self._hourly_model

    @Property(QObject, constant=True)
    def dailyModel(self):
        return self._daily_model

    @Property(QObject, constant=True)
    def locationModel(self):
        return self._location_model

    @Property(QObject, constant=True)
    def geocodeModel(self):
        return self._geocode_model

    @Property(QObject, constant=True)
    def currentConditions(self):
        return self._current

    @Property(QObject, constant=True)
    def dayDetail(self):
        return self._day_detail

    @Property(bool, notify=loadingChanged)
    def loading(self):
        return self._loading

    @Property(str, notify=errorChanged)
    def error(self):
        return self._error

    @Property(str, notify=lastUpdateChanged)
    def lastUpdate(self):
        return self._last_update

    # --- Actions ---

    @Slot()
    def refresh(self):
        """Fetch fresh forecast data for the active location."""
        loc = self._settings.activeLocation
        if loc is None:
            return

        self._loading = True
        self._error = ""
        self.loadingChanged.emit()
        self.errorChanged.emit()

        worker = ForecastWorker(loc["lat"], loc["lon"])
        worker.finished.connect(self._on_forecast)
        worker.error.connect(self._on_forecast_error)
        self._spawn(worker)

    def _on_forecast(self, data: dict):
        """Handle successful API response -- update all data models."""
        hourly = data.get("hourly", {})
        daily = data.get("daily", {})

        self._hourly_model.update(hourly)
        self._daily_model.update(daily)
        self._current.update_from_hourly(hourly, self._hourly_model.start_idx)

        self._loading = False
        self._last_update = datetime.now().strftime("%I:%M %p")
        self.loadingChanged.emit()
        self.lastUpdateChanged.emit()

    def _on_forecast_error(self, msg: str):
        self._loading = False
        self._error = msg
        self.loadingChanged.emit()
        self.errorChanged.emit()

    @Slot(str)
    def searchCity(self, query):
        """Trigger a geocode search.  Called by LocationSearchBar's debounce timer."""
        if len(query) < 2:
            self._geocode_model.clear()
            return

        worker = GeocodeWorker(query)
        worker.finished.connect(self._on_geocode)
        worker.error.connect(self._on_geocode_error)
        self._spawn(worker)

    def _on_geocode(self, results: list):
        self._geocode_model.update(results)

    def _on_geocode_error(self, msg: str):
        self._error = msg
        self.errorChanged.emit()

    @Slot(int)
    def addGeocodedLocation(self, index):
        """Save a search result as a location and fetch its weather."""
        result = self._geocode_model.get(index)
        if result:
            parts = [result.get("name", "")]
            if result.get("admin1"):
                parts.append(result["admin1"])
            name = ", ".join(parts)
            self._settings.addLocation(
                name, result["latitude"], result["longitude"]
            )
            self._geocode_model.clear()
            self.refresh()

    @Slot(str, float, float)
    def addManualLocation(self, name, lat, lon):
        """Save a manually-entered lat/lon location."""
        if not name:
            name = f"{lat:.2f}, {lon:.2f}"
        self._settings.addLocation(name, lat, lon)
        self.refresh()

    @Slot(int)
    def removeLocation(self, index):
        self._settings.removeLocation(index)

    @Slot(int)
    def setActiveLocation(self, index):
        """Switch to a different saved location (triggers refresh via signal)."""
        self._settings.activeLocationIndex = index

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

    # --- Background thread lifecycle ---

    def _spawn(self, worker):
        """Start a worker on its own thread and track it until it finishes.

        We keep the (thread, worker) pair in self._active so neither is GC'd
        while running, and reap it once the thread has fully stopped.
        """
        thread, worker = run_in_thread(worker)
        self._active.append((thread, worker))
        # thread.finished is emitted on the main thread once exec() returns,
        # so _reap runs where it's safe to drop the references and join.
        thread.finished.connect(lambda t=thread: self._reap(t))

    def _reap(self, thread):
        """Drop references to a thread that has finished running.

        Called on the main thread via thread.finished.  The thread is no
        longer running, so removing the last reference (and letting GC delete
        the QThread) is safe -- this is what avoids the "destroyed while
        running" abort without ever blocking the event loop.
        """
        thread.wait()  # returns immediately; just guarantees a clean join
        self._active = [(t, w) for (t, w) in self._active if t is not thread]

    # --- Shutdown ---

    def shutdown(self):
        """Stop all background threads before the app tears down.

        What: quit + join every active worker QThread (and stop the timer).
        Why:  a QThread destroyed while still running makes Qt call qFatal()
              ("QThread: Destroyed while thread is still running") -> SIGABRT.
              That happens if the user quits while an HTTP request is in-flight,
              because main.py's `del controller` then GC's a running QThread.
        How:  ask each thread's event loop to quit, then wait() to join it.
              The worker's run() is a blocking requests.get(), so quit() only
              takes effect once that call returns; we bound the wait and fall
              back to terminate() so shutdown can't hang on a stalled network.
        """
        self._refresh_timer.stop()
        # Copy the list: _reap() mutates self._active as threads finish.
        for thread, _worker in list(self._active):
            if not thread.isRunning():
                continue
            thread.quit()
            # Join, bounded to 3s. requests has its own 10-15s timeout, but we
            # don't want quitting the app to block that long on a hung socket.
            if not thread.wait(3000):
                thread.terminate()  # last resort; we're exiting anyway
                thread.wait()
