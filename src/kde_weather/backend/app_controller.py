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
from .api.worker import ForecastWorker, GeocodeWorker, run_in_thread
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

        self._loading = False
        self._error = ""
        self._last_update = ""

        # We must hold references to both the thread AND the worker to
        # prevent Python's GC from destroying them while the HTTP request
        # is in-flight.  Storing them as instance attrs keeps them alive.
        self._forecast_thread = None
        self._forecast_worker = None
        self._geocode_thread = None
        self._geocode_worker = None

        # Auto-refresh timer -- restarts whenever the interval changes
        self._refresh_timer = QTimer(self)
        self._refresh_timer.timeout.connect(self.refresh)
        self._update_timer_interval()

        # React to settings changes
        self._settings.refreshIntervalChanged.connect(self._update_timer_interval)
        self._settings.locationsChanged.connect(self._sync_location_model)
        self._settings.activeLocationIndexChanged.connect(self.refresh)

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
        # Store both refs -- see comment on _forecast_thread above
        self._forecast_thread, self._forecast_worker = run_in_thread(worker)

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
        self._geocode_thread, self._geocode_worker = run_in_thread(worker)

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
