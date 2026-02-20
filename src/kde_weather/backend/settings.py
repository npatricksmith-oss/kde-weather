"""
Persistent settings stored as JSON at ~/.config/kde-weather/settings.json.

Exposes all settings as Qt properties with change signals so QML can bind
directly to them.  Saves to disk on every mutation -- the file is small
(< 1 KB) so there's no need for batching or debouncing writes.

The enabled_elements map uses Open-Meteo API parameter names as keys
(e.g. "temperature_2m") so we can directly correlate which chart panels
to show and which API fields to request without any translation layer.
"""

import json
from pathlib import Path

from PySide6.QtCore import QObject, Signal, Slot, Property

CONFIG_DIR = Path.home() / ".config" / "kde-weather"
CONFIG_FILE = CONFIG_DIR / "settings.json"

# Default config for first launch.  Rain/snow off by default since they're
# zero most of the time and just add visual clutter.
DEFAULTS = {
    "locations": [],
    "active_location_index": -1,  # -1 = no location selected
    "refresh_interval_minutes": 30,
    "enabled_elements": {
        "temperature_2m": True,
        "apparent_temperature": True,
        "wind_speed_10m": True,
        "wind_gusts_10m": True,
        "relative_humidity_2m": True,
        "cloud_cover": True,
        "precipitation_probability": True,
        "rain": False,
        "snowfall": False,
        "snow_depth": False,
    },
}


class Settings(QObject):
    locationsChanged = Signal()
    activeLocationIndexChanged = Signal()
    refreshIntervalChanged = Signal()
    enabledElementsChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._data = dict(DEFAULTS)
        self._load()

    def _load(self):
        """Load saved settings from disk, merging with defaults.

        For enabled_elements we merge instead of replace so that newly
        added weather elements get their default value instead of being
        silently missing from an older config file.
        """
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE) as f:
                    saved = json.load(f)
                for k, v in saved.items():
                    if k in self._data:
                        if k == "enabled_elements":
                            self._data[k] = {**DEFAULTS["enabled_elements"], **v}
                        else:
                            self._data[k] = v
            except (json.JSONDecodeError, OSError):
                pass  # Corrupt/unreadable file -- fall back to defaults

    def _save(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(self._data, f, indent=2)

    # --- Locations ---

    @Property("QVariantList", notify=locationsChanged)
    def locations(self):
        return self._data["locations"]

    @Slot(str, float, float)
    def addLocation(self, name, lat, lon):
        self._data["locations"].append({"name": name, "lat": lat, "lon": lon})
        # Auto-select the first location added so the user sees data immediately
        if self._data["active_location_index"] < 0:
            self._data["active_location_index"] = 0
            self.activeLocationIndexChanged.emit()
        self.locationsChanged.emit()
        self._save()

    @Slot(int)
    def removeLocation(self, index):
        if 0 <= index < len(self._data["locations"]):
            self._data["locations"].pop(index)
            # Clamp the active index so it doesn't point past the end
            if self._data["active_location_index"] >= len(self._data["locations"]):
                self._data["active_location_index"] = max(0, len(self._data["locations"]) - 1)
                if not self._data["locations"]:
                    self._data["active_location_index"] = -1
                self.activeLocationIndexChanged.emit()
            self.locationsChanged.emit()
            self._save()

    # --- Active location ---

    @Property(int, notify=activeLocationIndexChanged)
    def activeLocationIndex(self):
        return self._data["active_location_index"]

    @activeLocationIndex.setter
    def activeLocationIndex(self, val):
        if val != self._data["active_location_index"]:
            self._data["active_location_index"] = val
            self.activeLocationIndexChanged.emit()
            self._save()

    @Property("QVariant", notify=activeLocationIndexChanged)
    def activeLocation(self):
        """Return the currently-selected location dict, or None."""
        idx = self._data["active_location_index"]
        locs = self._data["locations"]
        if 0 <= idx < len(locs):
            return locs[idx]
        return None

    # --- Refresh interval ---

    @Property(int, notify=refreshIntervalChanged)
    def refreshIntervalMinutes(self):
        return self._data["refresh_interval_minutes"]

    @refreshIntervalMinutes.setter
    def refreshIntervalMinutes(self, val):
        if val != self._data["refresh_interval_minutes"]:
            self._data["refresh_interval_minutes"] = val
            self.refreshIntervalChanged.emit()
            self._save()

    # --- Enabled elements ---

    @Property("QVariantMap", notify=enabledElementsChanged)
    def enabledElements(self):
        # Return a copy so QML sees it as a new object on each read,
        # ensuring property-change detection works correctly.
        return dict(self._data["enabled_elements"])

    @Slot(str, bool)
    def setElementEnabled(self, key, enabled):
        if key in self._data["enabled_elements"]:
            self._data["enabled_elements"][key] = enabled
            self.enabledElementsChanged.emit()
            self._save()

    @Slot(str, result=bool)
    def isElementEnabled(self, key):
        return self._data["enabled_elements"].get(key, False)
