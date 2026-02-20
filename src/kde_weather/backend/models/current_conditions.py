"""
QObject holding the "right now" weather snapshot for the header bar.

Populated from hourly_data[0] -- the first hour of the forecast, which
is the current hour.  We pull this from the hourly response rather than
using a separate "current weather" API endpoint because Open-Meteo's
current endpoint only has a subset of fields, and we already have the
hourly data anyway.

Uses a single "changed" signal for all properties because they always
update together (one API call refreshes everything at once), and having
10 individual signals would be pointless overhead.
"""

from PySide6.QtCore import QObject, Signal, Property


class CurrentConditions(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._temp = 0.0
        self._feels_like = 0.0
        self._humidity = 0
        self._wind_speed = 0.0
        self._wind_gusts = 0.0
        self._wind_dir = 0
        self._weather_code = 0
        self._description = ""
        self._precip_prob = 0
        self._cloud_cover = 0

    def _notify(self):
        self.changed.emit()

    @Property(float, notify=changed)
    def temperature(self):
        return self._temp

    @Property(float, notify=changed)
    def feelsLike(self):
        return self._feels_like

    @Property(int, notify=changed)
    def humidity(self):
        return self._humidity

    @Property(float, notify=changed)
    def windSpeed(self):
        return self._wind_speed

    @Property(float, notify=changed)
    def windGusts(self):
        return self._wind_gusts

    @Property(int, notify=changed)
    def windDirection(self):
        return self._wind_dir

    @Property(int, notify=changed)
    def weatherCode(self):
        return self._weather_code

    @Property(str, notify=changed)
    def description(self):
        return self._description

    @Property(int, notify=changed)
    def precipProbability(self):
        return self._precip_prob

    @Property(int, notify=changed)
    def cloudCover(self):
        return self._cloud_cover

    def update_from_hourly(self, hourly: dict):
        """Extract index-0 values from each hourly array for current conditions."""
        def _get(key, idx=0, default=0):
            vals = hourly.get(key, [])
            return vals[idx] if idx < len(vals) else default

        self._temp = float(_get("temperature_2m", 0, 0))
        self._feels_like = float(_get("apparent_temperature", 0, 0))
        self._humidity = int(_get("relative_humidity_2m", 0, 0))
        self._wind_speed = float(_get("wind_speed_10m", 0, 0))
        self._wind_gusts = float(_get("wind_gusts_10m", 0, 0))
        self._wind_dir = int(_get("wind_direction_10m", 0, 0))
        self._weather_code = int(_get("weather_code", 0, 0))
        self._precip_prob = int(_get("precipitation_probability", 0, 0))
        self._cloud_cover = int(_get("cloud_cover", 0, 0))
        self._description = WMO_DESCRIPTIONS.get(self._weather_code, "Unknown")
        self._notify()


# WMO Weather interpretation codes (WW)
# https://www.nodc.noaa.gov/archive/arc0021/0002199/1.1/data/0-data/HTML/WMO-CODE/WMO4677.HTM
WMO_DESCRIPTIONS = {
    0: "Clear sky",
    1: "Mainly clear",
    2: "Partly cloudy",
    3: "Overcast",
    45: "Fog",
    48: "Depositing rime fog",
    51: "Light drizzle",
    53: "Moderate drizzle",
    55: "Dense drizzle",
    56: "Light freezing drizzle",
    57: "Dense freezing drizzle",
    61: "Slight rain",
    63: "Moderate rain",
    65: "Heavy rain",
    66: "Light freezing rain",
    67: "Heavy freezing rain",
    71: "Slight snowfall",
    73: "Moderate snowfall",
    75: "Heavy snowfall",
    77: "Snow grains",
    80: "Slight rain showers",
    81: "Moderate rain showers",
    82: "Violent rain showers",
    85: "Slight snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm with slight hail",
    99: "Thunderstorm with heavy hail",
}
