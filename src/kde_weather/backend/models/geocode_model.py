"""
QAbstractListModel for city search (geocoding) results.

Populated by AppController.searchCity() -> GeocodeWorker -> _on_geocode().
The results are displayed in LocationSearchBar.qml as an autocomplete
dropdown.  When the user clicks a result, addGeocodedLocation(index) is
called, which reads the raw result dict via get() and saves it.

The DisplayRole builds a "City, State, Country" string for the dropdown --
Open-Meteo's geocoding API returns these as separate fields (name, admin1,
country) so we join them here.
"""

from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex


class GeocodeModel(QAbstractListModel):
    NameRole = Qt.UserRole + 1
    AdminRole = Qt.UserRole + 2
    CountryRole = Qt.UserRole + 3
    LatRole = Qt.UserRole + 4
    LonRole = Qt.UserRole + 5
    DisplayRole = Qt.UserRole + 6

    def __init__(self, parent=None):
        super().__init__(parent)
        self._results = []

    def roleNames(self):
        return {
            self.NameRole: b"name",
            self.AdminRole: b"admin",
            self.CountryRole: b"country",
            self.LatRole: b"lat",
            self.LonRole: b"lon",
            self.DisplayRole: b"display",
        }

    def rowCount(self, parent=QModelIndex()):
        return len(self._results)

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid() or index.row() >= len(self._results):
            return None
        r = self._results[index.row()]
        if role == self.NameRole:
            return r.get("name", "")
        if role == self.AdminRole:
            return r.get("admin1", "")
        if role == self.CountryRole:
            return r.get("country", "")
        if role == self.LatRole:
            return r.get("latitude", 0.0)
        if role == self.LonRole:
            return r.get("longitude", 0.0)
        if role == self.DisplayRole:
            parts = [r.get("name", "")]
            if r.get("admin1"):
                parts.append(r["admin1"])
            if r.get("country"):
                parts.append(r["country"])
            return ", ".join(parts)
        return None

    def update(self, results: list):
        self.beginResetModel()
        self._results = list(results)
        self.endResetModel()

    def clear(self):
        """Empty the results, e.g. after the user selects a result."""
        self.beginResetModel()
        self._results = []
        self.endResetModel()

    def get(self, index: int) -> dict | None:
        """Return the raw API result dict at index for saving to settings."""
        if 0 <= index < len(self._results):
            return self._results[index]
        return None
