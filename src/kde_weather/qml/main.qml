import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "theme"
import "components"
import "views"

// Root window for KDE Weather.
//
// Layout structure:
//   header: ToolBar with location ComboBox, status indicators, refresh/settings buttons
//   body:   CurrentConditions bar + TabBar (48-Hour | 7-Day) + StackLayout
//   drawer: Settings panel that slides from the right edge
//
// All data access goes through the "app" context property (AppController),
// set in main.py.  QML never makes API calls directly.

ApplicationWindow {
    id: window
    visible: true
    width: 900
    height: 700
    minimumWidth: 600
    minimumHeight: 500
    title: "KDE Weather"
    color: Theme.background

    // --- Header toolbar ---
    header: ToolBar {
        background: Rectangle { color: Theme.surface }
        height: 48

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingLarge
            anchors.rightMargin: Theme.spacingLarge
            spacing: Theme.spacingMedium

            // Location selector -- bound to the location model so it
            // auto-updates when locations are added/removed
            ComboBox {
                id: locationCombo
                Layout.preferredWidth: 200
                model: app.locationModel
                textRole: "name"
                currentIndex: app.settings.activeLocationIndex
                visible: app.locationModel.rowCount() > 0

                onActivated: app.setActiveLocation(currentIndex)

                background: Rectangle {
                    color: Theme.surfaceAlt
                    radius: Theme.radiusSmall
                    border.color: Theme.border
                }
                contentItem: Text {
                    text: locationCombo.displayText
                    color: Theme.text
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: Theme.spacingMedium
                    elide: Text.ElideRight
                }
            }

            // Shown when no locations exist yet
            Text {
                text: "No locations configured"
                color: Theme.textSecondary
                font.pixelSize: 13
                visible: app.locationModel.rowCount() === 0
            }

            Item { Layout.fillWidth: true }

            // Spinner while API request is in-flight
            BusyIndicator {
                running: app.loading
                visible: app.loading
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
            }

            // Error message from failed API calls
            Text {
                text: app.error
                color: Theme.error
                font.pixelSize: 11
                visible: app.error !== ""
                Layout.maximumWidth: 200
                elide: Text.ElideRight
            }

            // Timestamp of last successful refresh
            Text {
                text: app.lastUpdate ? "Updated " + app.lastUpdate : ""
                color: Theme.textDisabled
                font.pixelSize: 11
                visible: app.lastUpdate !== ""
            }

            // Manual refresh button
            ToolButton {
                text: "\u21bb"  // Unicode clockwise arrows
                font.pixelSize: 18
                onClicked: app.refresh()
                enabled: !app.loading

                contentItem: Text {
                    text: parent.text
                    color: Theme.text
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                    radius: Theme.radiusSmall
                }
            }

            // Settings gear -- opens the drawer
            ToolButton {
                text: "\u2699"  // Unicode gear
                font.pixelSize: 20
                onClicked: settingsDrawer.open()

                contentItem: Text {
                    text: parent.text
                    color: Theme.text
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: parent.hovered ? Theme.surfaceAlt : "transparent"
                    radius: Theme.radiusSmall
                }
            }
        }
    }

    // --- Main content area ---
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingMedium

        // Current weather summary bar
        CurrentConditions {
            Layout.fillWidth: true
            visible: app.settings.activeLocationIndex >= 0
        }

        // Empty state prompt when no location is configured
        Text {
            text: "Open Settings to add a location"
            color: Theme.textSecondary
            font.pixelSize: 16
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 100
            visible: app.settings.activeLocationIndex < 0
        }

        // Tab bar for switching between hourly and daily views
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            visible: app.settings.activeLocationIndex >= 0

            background: Rectangle { color: "transparent" }

            TabButton {
                text: "48-Hour Hourly"
                width: implicitWidth
                contentItem: Text {
                    text: parent.text
                    color: tabBar.currentIndex === 0 ? Theme.accent : Theme.textSecondary
                    font.pixelSize: 13
                    font.bold: tabBar.currentIndex === 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: tabBar.currentIndex === 0 ? Theme.surfaceAlt : "transparent"
                    radius: Theme.radiusSmall
                }
            }

            TabButton {
                text: "7-Day Forecast"
                width: implicitWidth
                contentItem: Text {
                    text: parent.text
                    color: tabBar.currentIndex === 1 ? Theme.accent : Theme.textSecondary
                    font.pixelSize: 13
                    font.bold: tabBar.currentIndex === 1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: tabBar.currentIndex === 1 ? Theme.surfaceAlt : "transparent"
                    radius: Theme.radiusSmall
                }
            }
        }

        // Tab content -- StackLayout shows one child at a time
        StackLayout {
            currentIndex: tabBar.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: app.settings.activeLocationIndex >= 0

            HourlyView {}
            DailyView {}
        }
    }

    // --- Settings drawer (slides from right) ---
    Drawer {
        id: settingsDrawer
        width: Math.min(400, window.width * 0.8)
        height: window.height
        edge: Qt.RightEdge
        modal: true

        background: Rectangle {
            color: Theme.background
            // Left border line to visually separate drawer from main content
            Rectangle {
                width: 1
                height: parent.height
                color: Theme.border
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Drawer title bar
            Rectangle {
                Layout.fillWidth: true
                height: 48
                color: Theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMedium

                    Text {
                        text: "Settings"
                        font.pixelSize: 16
                        font.bold: true
                        color: Theme.text
                        Layout.fillWidth: true
                    }

                    ToolButton {
                        text: "\u2715"  // Unicode X mark
                        onClicked: settingsDrawer.close()
                        contentItem: Text {
                            text: parent.text
                            color: Theme.text
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                        }
                        background: Rectangle {
                            color: parent.hovered ? Theme.surfaceAlt : "transparent"
                            radius: Theme.radiusSmall
                        }
                    }
                }
            }

            SettingsView {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
