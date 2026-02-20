"""
QThread workers for non-blocking API calls.

We use the "worker object" pattern instead of subclassing QThread:
  1. Create a QObject worker with a run() slot
  2. Move it to a QThread
  3. Connect thread.started -> worker.run
  4. Worker emits finished/error signals back to the main thread

This keeps the HTTP call off the main thread so the UI stays responsive.

IMPORTANT: The caller must hold references to both the thread AND the
worker object.  If Python GC's the worker while the thread is running,
the app segfaults.  See run_in_thread() return value and how
AppController stores both in _forecast_thread/_forecast_worker.
"""

from PySide6.QtCore import QObject, QThread, Signal, Slot

from .open_meteo import fetch_forecast, fetch_geocode


class ForecastWorker(QObject):
    finished = Signal(dict)  # Emits the full API response dict
    error = Signal(str)      # Emits the exception message on failure

    def __init__(self, lat, lon):
        super().__init__()
        self._lat = lat
        self._lon = lon

    @Slot()
    def run(self):
        try:
            data = fetch_forecast(self._lat, self._lon)
            self.finished.emit(data)
        except Exception as e:
            self.error.emit(str(e))


class GeocodeWorker(QObject):
    finished = Signal(list)  # Emits list of geocode result dicts
    error = Signal(str)

    def __init__(self, query):
        super().__init__()
        self._query = query

    @Slot()
    def run(self):
        try:
            results = fetch_geocode(self._query)
            self.finished.emit(results)
        except Exception as e:
            self.error.emit(str(e))


def run_in_thread(worker):
    """Move a worker QObject to a new QThread and start it.

    Returns (thread, worker) -- the caller MUST store both references
    to prevent premature garbage collection.  The thread is stopped and
    cleaned up when the worker emits finished or error.
    """
    thread = QThread()
    worker.moveToThread(thread)
    thread.started.connect(worker.run)

    def cleanup():
        thread.quit()
        thread.wait()

    worker.finished.connect(cleanup)
    worker.error.connect(cleanup)
    thread.start()
    return thread, worker
