"""
Entry point for KDE Weather.

Sets up PySide6 with the Fusion widget style and a hand-tuned Breeze Dark
palette, then boots the QML UI.  We use Fusion (Qt's cross-platform style)
instead of the native KDE/Breeze widget style because it lets us set an
exact palette without fighting the platform theme plugin -- Breeze-the-
style applies its own palette and ignores ours.
"""

import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QColor, QPalette, QFont
from PySide6.QtWidgets import QApplication
from PySide6.QtQml import QQmlApplicationEngine

from .backend.app_controller import AppController


def build_breeze_dark_palette():
    """Build a QPalette that matches KDE Breeze Dark color values.

    These hex values are pulled from the Breeze Dark color scheme file
    (/usr/share/color-schemes/BreezeDark.colors).  We apply them
    explicitly so the app looks correct even outside a KDE Plasma session.
    """
    p = QPalette()
    p.setColor(QPalette.Window, QColor("#141618"))
    p.setColor(QPalette.WindowText, QColor("#fcfcfc"))
    p.setColor(QPalette.Base, QColor("#1b1e20"))
    p.setColor(QPalette.AlternateBase, QColor("#232629"))
    p.setColor(QPalette.ToolTipBase, QColor("#31363b"))
    p.setColor(QPalette.ToolTipText, QColor("#fcfcfc"))
    p.setColor(QPalette.Text, QColor("#fcfcfc"))
    p.setColor(QPalette.Button, QColor("#31363b"))
    p.setColor(QPalette.ButtonText, QColor("#fcfcfc"))
    p.setColor(QPalette.BrightText, QColor("#ffffff"))
    p.setColor(QPalette.Link, QColor("#3daee9"))
    p.setColor(QPalette.Highlight, QColor("#3daee9"))
    p.setColor(QPalette.HighlightedText, QColor("#fcfcfc"))
    p.setColor(QPalette.Disabled, QPalette.Text, QColor("#6e7175"))
    p.setColor(QPalette.Disabled, QPalette.ButtonText, QColor("#6e7175"))
    return p


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("KDE Weather")
    app.setOrganizationName("kde-weather")
    app.setStyle("Fusion")
    app.setPalette(build_breeze_dark_palette())

    controller = AppController()

    engine = QQmlApplicationEngine()
    # Expose the controller to QML as "app" -- every QML file accesses
    # models, settings, and actions through this single context property.
    engine.rootContext().setContextProperty("app", controller)

    qml_dir = Path(__file__).parent / "qml"
    # Add qml/ as an import path so QML can resolve "theme", "components",
    # and "views" as local module imports.
    engine.addImportPath(str(qml_dir))
    engine.load(QUrl.fromLocalFile(str(qml_dir / "main.qml")))

    if not engine.rootObjects():
        print("Error: Failed to load QML", file=sys.stderr)
        sys.exit(1)

    ret = app.exec()

    # PySide6 crashes on shutdown if Python's GC destroys Qt objects in the
    # wrong order (engine refs QML objects that ref the controller).  We
    # force the correct teardown sequence: engine first, then controller,
    # then app.
    del engine
    del controller
    del app

    sys.exit(ret)


if __name__ == "__main__":
    main()
