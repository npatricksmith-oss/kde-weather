"""
QAbstractListModel for the 7-day daily forecast.

Each row represents one day with high/low temps, precipitation summary,
wind max, weather code, and sunrise/sunset times.  Used by DailyView.qml's
Repeater to render DayCard components.

The _KEYS table centralizes the (role, api_key) mapping so we don't
repeat it across roleNames(), data(), and update().
"""

from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex


class DailyModel(QAbstractListModel):
    DateRole = Qt.UserRole + 1
    TempMaxRole = Qt.UserRole + 2
    TempMinRole = Qt.UserRole + 3
    ApparentMaxRole = Qt.UserRole + 4
    ApparentMinRole = Qt.UserRole + 5
    PrecipProbMaxRole = Qt.UserRole + 6
    PrecipSumRole = Qt.UserRole + 7
    RainSumRole = Qt.UserRole + 8
    SnowfallSumRole = Qt.UserRole + 9
    WindMaxRole = Qt.UserRole + 10
    GustMaxRole = Qt.UserRole + 11
    WeatherCodeRole = Qt.UserRole + 12
    SunriseRole = Qt.UserRole + 13
    SunsetRole = Qt.UserRole + 14

    # Single source of truth: (Qt role, Open-Meteo API key)
    _KEYS = [
        (DateRole, "time"),
        (TempMaxRole, "temperature_2m_max"),
        (TempMinRole, "temperature_2m_min"),
        (ApparentMaxRole, "apparent_temperature_max"),
        (ApparentMinRole, "apparent_temperature_min"),
        (PrecipProbMaxRole, "precipitation_probability_max"),
        (PrecipSumRole, "precipitation_sum"),
        (RainSumRole, "rain_sum"),
        (SnowfallSumRole, "snowfall_sum"),
        (WindMaxRole, "wind_speed_10m_max"),
        (GustMaxRole, "wind_gusts_10m_max"),
        (WeatherCodeRole, "weather_code"),
        (SunriseRole, "sunrise"),
        (SunsetRole, "sunset"),
    ]

    def __init__(self, parent=None):
        super().__init__(parent)
        self._rows = []

    def roleNames(self):
        """Map role enums to QML property names for delegate access."""
        names = {
            self.DateRole: b"date",
            self.TempMaxRole: b"tempMax",
            self.TempMinRole: b"tempMin",
            self.ApparentMaxRole: b"apparentMax",
            self.ApparentMinRole: b"apparentMin",
            self.PrecipProbMaxRole: b"precipProbMax",
            self.PrecipSumRole: b"precipSum",
            self.RainSumRole: b"rainSum",
            self.SnowfallSumRole: b"snowfallSum",
            self.WindMaxRole: b"windMax",
            self.GustMaxRole: b"gustMax",
            self.WeatherCodeRole: b"weatherCode",
            self.SunriseRole: b"sunrise",
            self.SunsetRole: b"sunset",
        }
        return names

    def rowCount(self, parent=QModelIndex()):
        return len(self._rows)

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid() or index.row() >= len(self._rows):
            return None
        row = self._rows[index.row()]
        for r, key in self._KEYS:
            if role == r:
                return row.get(key)
        return None

    def update(self, daily_data: dict):
        """Replace all rows with fresh API daily data.

        Open-Meteo returns daily arrays keyed by parameter name, all the
        same length.  We pivot them into per-day row dicts for the model.
        """
        self.beginResetModel()
        times = daily_data.get("time", [])
        self._rows = []
        for i in range(len(times)):
            row = {}
            for _, key in self._KEYS:
                vals = daily_data.get(key, [])
                row[key] = vals[i] if i < len(vals) else None
            self._rows.append(row)
        self.endResetModel()
