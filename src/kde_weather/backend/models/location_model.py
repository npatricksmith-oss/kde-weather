"""
QAbstractListModel for the user's saved locations.

This is a read-only mirror of Settings.locations -- the controller calls
update() whenever Settings.locationsChanged fires.  We need a separate
model (rather than exposing the settings list directly) because QML's
ComboBox and Repeater require a proper QAbstractItemModel with roleNames.
"""

from PySide6.QtCore import QAbstractListModel, Qt, QModelIndex


class LocationModel(QAbstractListModel):
    NameRole = Qt.UserRole + 1
    LatRole = Qt.UserRole + 2
    LonRole = Qt.UserRole + 3

    def __init__(self, parent=None):
        super().__init__(parent)
        self._locations = []

    def roleNames(self):
        return {
            self.NameRole: b"name",
            self.LatRole: b"lat",
            self.LonRole: b"lon",
        }

    def rowCount(self, parent=QModelIndex()):
        return len(self._locations)

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid() or index.row() >= len(self._locations):
            return None
        loc = self._locations[index.row()]
        if role == self.NameRole:
            return loc.get("name", "")
        if role == self.LatRole:
            return loc.get("lat", 0.0)
        if role == self.LonRole:
            return loc.get("lon", 0.0)
        return None

    def update(self, locations: list):
        """Replace all rows.  Called by AppController._sync_location_model."""
        self.beginResetModel()
        self._locations = list(locations)
        self.endResetModel()
