"""
QAbstractListModel for 48-hour hourly forecast data.

This model serves two purposes:
  1. Standard list model for any QML ListView/Repeater that wants row-level
     access via role names (e.g. model.temperature, model.humidity)
  2. Chart data provider via seriesData() -- returns pre-formatted [{x, y}]
     arrays that WeatherChart.qml can feed directly to a SplineSeries

The 48-hour window is a deliberate cap.  Open-Meteo returns 168 hours
(7 days) of hourly data, but beyond 48 hours the hourly view gets too
wide and the daily view is more useful.

dataVersion / dataVersionChanged:
  QML declarative bindings can't detect when a Slot method like
  seriesData() would return different results.  We increment dataVersion
  after each update() so QML can bind to it as a dependency trigger --
  when it changes, HourlyView.qml imperatively re-calls seriesData()
  for each chart.  This is the standard workaround for "imperative data
  in a declarative binding world" in Qt Quick.
"""

from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex, Slot, Signal, Property


class HourlyModel(QAbstractListModel):
    dataVersionChanged = Signal()

    # Custom roles for QML access.  Qt requires roles > Qt.UserRole.
    TimeRole = Qt.UserRole + 1
    TempRole = Qt.UserRole + 2
    ApparentTempRole = Qt.UserRole + 3
    HumidityRole = Qt.UserRole + 4
    PrecipProbRole = Qt.UserRole + 5
    RainRole = Qt.UserRole + 6
    SnowfallRole = Qt.UserRole + 7
    SnowDepthRole = Qt.UserRole + 8
    CloudCoverRole = Qt.UserRole + 9
    WindSpeedRole = Qt.UserRole + 10
    WindGustsRole = Qt.UserRole + 11
    WindDirRole = Qt.UserRole + 12
    WeatherCodeRole = Qt.UserRole + 13

    def __init__(self, parent=None):
        super().__init__(parent)
        self._rows = []
        self._data_version = 0

    @Property(int, notify=dataVersionChanged)
    def dataVersion(self):
        return self._data_version

    def roleNames(self):
        """Map role enums to QML-accessible property names."""
        return {
            self.TimeRole: b"time",
            self.TempRole: b"temperature",
            self.ApparentTempRole: b"apparentTemperature",
            self.HumidityRole: b"humidity",
            self.PrecipProbRole: b"precipProbability",
            self.RainRole: b"rain",
            self.SnowfallRole: b"snowfall",
            self.SnowDepthRole: b"snowDepth",
            self.CloudCoverRole: b"cloudCover",
            self.WindSpeedRole: b"windSpeed",
            self.WindGustsRole: b"windGusts",
            self.WindDirRole: b"windDirection",
            self.WeatherCodeRole: b"weatherCode",
        }

    def rowCount(self, parent=QModelIndex()):
        return len(self._rows)

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid() or index.row() >= len(self._rows):
            return None
        row = self._rows[index.row()]
        # Map Qt role enum -> Open-Meteo API key name
        role_map = {
            self.TimeRole: "time",
            self.TempRole: "temperature_2m",
            self.ApparentTempRole: "apparent_temperature",
            self.HumidityRole: "relative_humidity_2m",
            self.PrecipProbRole: "precipitation_probability",
            self.RainRole: "rain",
            self.SnowfallRole: "snowfall",
            self.SnowDepthRole: "snow_depth",
            self.CloudCoverRole: "cloud_cover",
            self.WindSpeedRole: "wind_speed_10m",
            self.WindGustsRole: "wind_gusts_10m",
            self.WindDirRole: "wind_direction_10m",
            self.WeatherCodeRole: "weather_code",
        }
        key = role_map.get(role)
        if key:
            return row.get(key)
        return None

    def update(self, hourly_data: dict):
        """Replace all rows with fresh API data, capped at 48 hours.

        Called from AppController._on_forecast() on the main thread after
        the worker thread delivers the API response.
        """
        self.beginResetModel()
        times = hourly_data.get("time", [])
        count = min(len(times), 48)
        self._rows = []
        for i in range(count):
            row = {"time": times[i]}
            for key in [
                "temperature_2m", "apparent_temperature", "relative_humidity_2m",
                "precipitation_probability", "rain", "snowfall", "snow_depth",
                "cloud_cover", "wind_speed_10m", "wind_gusts_10m",
                "wind_direction_10m", "weather_code",
            ]:
                vals = hourly_data.get(key, [])
                row[key] = vals[i] if i < len(vals) else None
            self._rows.append(row)
        self.endResetModel()
        # Bump version so QML knows to re-fetch chart series data
        self._data_version += 1
        self.dataVersionChanged.emit()

    @Slot(str, result=list)
    def seriesData(self, key):
        """Return [{x: hourIndex, y: value}, ...] for a given weather element.

        The key uses QML-friendly camelCase names (e.g. "windSpeed") which
        we map back to API names internally.  This format is consumed
        directly by WeatherChart.qml's updateChart() function to populate
        SplineSeries point-by-point.
        """
        role_key_map = {
            "temperature": "temperature_2m",
            "apparentTemperature": "apparent_temperature",
            "humidity": "relative_humidity_2m",
            "precipProbability": "precipitation_probability",
            "rain": "rain",
            "snowfall": "snowfall",
            "snowDepth": "snow_depth",
            "cloudCover": "cloud_cover",
            "windSpeed": "wind_speed_10m",
            "windGusts": "wind_gusts_10m",
        }
        api_key = role_key_map.get(key, key)
        result = []
        for i, row in enumerate(self._rows):
            val = row.get(api_key)
            if val is not None:
                result.append({"x": i, "y": float(val)})
        return result

    @Slot(result=list)
    def timeLabels(self):
        """Return ISO time strings for x-axis labeling."""
        return [row.get("time", "") for row in self._rows]
