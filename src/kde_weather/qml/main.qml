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
        // Taller than the legacy 48px to fit 2x larger fonts
        height: 64

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacingLarge
            anchors.rightMargin: Theme.spacingLarge
            spacing: Theme.spacingMedium

            // Location selector -- bound to the location model so it
            // auto-updates when locations are added/removed
            ComboBox {
                id: locationCombo
                Layout.preferredWidth: 260
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
                    // 2x the legacy 13px body size
                    font.pixelSize: Theme.fontBody
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: Theme.spacingMedium
                    elide: Text.ElideRight
                }
            }

            // Shown when no locations exist yet
            Text {
                text: "No locations configured"
                color: Theme.textSecondary
                // 2x the legacy 13px body size
                font.pixelSize: Theme.fontBody
                visible: app.locationModel.rowCount() === 0
            }

            Item { Layout.fillWidth: true }

            // Spinner while API request is in-flight
            BusyIndicator {
                running: app.loading
                visible: app.loading
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
            }

            // Error message from failed API calls
            Text {
                text: app.error
                color: Theme.error
                // 2x the legacy 11px secondary size
                font.pixelSize: Theme.fontSecondary
                visible: app.error !== ""
                Layout.maximumWidth: 260
                elide: Text.ElideRight
            }

            // Timestamp of last successful refresh
            Text {
                text: app.lastUpdate ? "Updated " + app.lastUpdate : ""
                color: Theme.textDisabled
                // 2x the legacy 11px secondary size
                font.pixelSize: Theme.fontSecondary
                visible: app.lastUpdate !== ""
            }

            // Manual refresh button
            ToolButton {
                text: "\u21bb"  // Unicode clockwise arrows
                onClicked: app.refresh()
                enabled: !app.loading

                contentItem: Text {
                    text: parent.text
                    color: Theme.text
                    // 2x the legacy 18px icon size
                    font.pixelSize: 36
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
                onClicked: settingsDrawer.open()

                contentItem: Text {
                    text: parent.text
                    color: Theme.text
                    // 2x the legacy 20px icon size
                    font.pixelSize: 40
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
            // 2x the legacy 16px title size
            font.pixelSize: Theme.fontTitle
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 100
            visible: app.settings.activeLocationIndex < 0
        }

        // Tab bar for switching between hourly and daily views.
        //
        // Each TabButton fills exactly half the bar (width: tabBar.width / 2)
        // to prevent overlap.  Previously, width: implicitWidth was used, but
        // with a custom contentItem the implicitWidth is unreliable and the two
        // buttons can overlap or leave gaps.
        //
        // Visual hierarchy: the bar sits on Theme.surface; the active tab
        // is Theme.surfaceAlt (lighter) with an accent-colored bottom indicator;
        // the inactive tab is Theme.surface (matching the bar background, no
        // indicator) so the active one pops without needing a hard border.
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            // Explicit height prevents the bar from collapsing to its default
            // Qt implicitHeight (48 px), which is too cramped for a 26 px font.
            height: 54
            visible: app.settings.activeLocationIndex >= 0

            // Visible card behind both tabs so there is a clear "tab strip" region
            background: Rectangle {
                color: Theme.surface
                radius: Theme.radiusSmall
            }

            TabButton {
                text: "48-Hour Hourly"
                // Equal split: each of the two tabs owns exactly half the bar.
                // This replaces the old width: implicitWidth which caused overlap.
                width: tabBar.width / 2
                height: tabBar.height
                contentItem: Text {
                    text: parent.text
                    color: tabBar.currentIndex === 0 ? Theme.accent : Theme.textSecondary
                    font.pixelSize: Theme.fontBody
                    font.bold: tabBar.currentIndex === 0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    // Active: surfaceAlt (lighter than bar) so it stands out clearly.
                    // Inactive: surface (same as bar) so inactive tabs are flush.
                    color: tabBar.currentIndex === 0 ? Theme.surfaceAlt : Theme.surface
                    radius: Theme.radiusSmall

                    // Accent-colored bottom indicator line for the active tab.
                    // Only rendered when this tab is active; otherwise invisible.
                    Rectangle {
                        visible: tabBar.currentIndex === 0
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingSmall
                        anchors.rightMargin: Theme.spacingSmall
                        height: 3
                        radius: 2
                        color: Theme.accent
                    }
                }
            }

            TabButton {
                text: "7-Day Forecast"
                width: tabBar.width / 2
                height: tabBar.height
                contentItem: Text {
                    text: parent.text
                    color: tabBar.currentIndex === 1 ? Theme.accent : Theme.textSecondary
                    font.pixelSize: Theme.fontBody
                    font.bold: tabBar.currentIndex === 1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: tabBar.currentIndex === 1 ? Theme.surfaceAlt : Theme.surface
                    radius: Theme.radiusSmall

                    Rectangle {
                        visible: tabBar.currentIndex === 1
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.spacingSmall
                        anchors.rightMargin: Theme.spacingSmall
                        height: 3
                        radius: 2
                        color: Theme.accent
                    }
                }
            }
        }

        // Tab content -- StackLayout shows one child at a time.
        // When the hourly tab is selected, we force focus to the HourlyView
        // so that Up/Down arrow keys immediately scroll without needing a click.
        StackLayout {
            currentIndex: tabBar.currentIndex
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: app.settings.activeLocationIndex >= 0

            onCurrentIndexChanged: {
                if (currentIndex === 0) hourlyView.forceActiveFocus()
            }

            HourlyView { id: hourlyView }
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
                height: 64
                color: Theme.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMedium

                    Text {
                        text: "Settings"
                        // 2x the legacy 16px title size
                        font.pixelSize: Theme.fontTitle
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
                            // 2x the legacy 16px title size
                            font.pixelSize: Theme.fontTitle
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
