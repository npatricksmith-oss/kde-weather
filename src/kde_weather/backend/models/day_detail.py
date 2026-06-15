"""QObject exposing the currently-selected day's NWS detail to QML.

What: holds selection + loading/error/availability state and the parsed
      narrative periods and alerts for the day the user clicked.
Why:  QML binds to app.dayDetail.* so the 7-Day detail panel reacts to fetches.
How:  one `changed` signal backs every property; QML re-reads them all whenever
      any mutator fires. Mutators are the only way state changes, keeping each
      transition explicit (select -> loading -> data | unavailable | error).
"""
from PySide6.QtCore import QObject, Signal, Property


class DayDetail(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._selected_date = ""   # "" means collapsed / nothing selected
        self._loading = False
        self._error = ""
        self._available = True
        self._periods = []         # list of {"name", "text"}
        self._alerts = []          # list of {"event","headline","severity","text","expiresText"}

    @Property(str, notify=changed)
    def selectedDate(self):
        return self._selected_date

    @Property(bool, notify=changed)
    def loading(self):
        return self._loading

    @Property(str, notify=changed)
    def error(self):
        return self._error

    @Property(bool, notify=changed)
    def available(self):
        return self._available

    @Property(list, notify=changed)
    def periods(self):
        return self._periods

    @Property(list, notify=changed)
    def alerts(self):
        return self._alerts

    # --- mutators (each emits `changed` exactly once) ---

    def select(self, date_str):
        """Begin showing date_str; reset prior data to a clean pre-load state."""
        self._selected_date = date_str
        self._loading = False
        self._error = ""
        self._available = True
        self._periods = []
        self._alerts = []
        self.changed.emit()

    def clear(self):
        """Collapse the panel (no day selected)."""
        self._selected_date = ""
        self._loading = False
        self._error = ""
        self._available = True
        self._periods = []
        self._alerts = []
        self.changed.emit()

    def set_loading(self):
        self._loading = True
        self._error = ""
        self.changed.emit()

    def set_unavailable(self):
        self._loading = False
        self._available = False
        self._periods = []
        self._alerts = []
        self.changed.emit()

    def set_error(self, msg):
        self._loading = False
        self._error = msg
        self.changed.emit()

    def set_data(self, periods, alerts):
        self._loading = False
        self._error = ""
        self._available = True
        self._periods = periods
        self._alerts = alerts
        self.changed.emit()
