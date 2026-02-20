import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "../components"

// Settings panel displayed inside a Drawer (slides from right edge).
// Contains four sections:
//   1. City search (autocomplete via Open-Meteo geocoding)
//   2. Manual lat/lon entry (for locations not in the geocoding DB)
//   3. Saved locations list (click to select, X to delete)
//   4. Weather element checkboxes (controls which hourly charts are visible)
//   5. Refresh interval selector (15/30/60 minute buttons)

Rectangle {
    id: root
    color: Theme.background

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        contentHeight: content.height
        clip: true

        ColumnLayout {
            id: content
            width: parent.width
            spacing: Theme.spacingLarge

            // --- Section 1: City search ---
            Text {
                text: "Add Location"
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
            }

            LocationSearchBar {
                Layout.fillWidth: true
            }

            // --- Section 2: Manual coordinates ---
            Text {
                text: "Manual Coordinates"
                font.pixelSize: 14
                font.bold: true
                color: Theme.text
                Layout.topMargin: Theme.spacingMedium
            }

            GridLayout {
                columns: 2
                columnSpacing: Theme.spacingMedium
                rowSpacing: Theme.spacingSmall
                Layout.fillWidth: true

                Text { text: "Name"; color: Theme.textSecondary; font.pixelSize: 12 }
                TextField {
                    id: manualName
                    Layout.fillWidth: true
                    placeholderText: "Location name"
                    color: Theme.text
                    placeholderTextColor: Theme.textDisabled
                    background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall; border.color: Theme.border }
                }

                Text { text: "Latitude"; color: Theme.textSecondary; font.pixelSize: 12 }
                TextField {
                    id: manualLat
                    Layout.fillWidth: true
                    placeholderText: "e.g. 39.7392"
                    color: Theme.text
                    placeholderTextColor: Theme.textDisabled
                    validator: DoubleValidator { bottom: -90; top: 90 }
                    background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall; border.color: Theme.border }
                }

                Text { text: "Longitude"; color: Theme.textSecondary; font.pixelSize: 12 }
                TextField {
                    id: manualLon
                    Layout.fillWidth: true
                    placeholderText: "e.g. -104.9903"
                    color: Theme.text
                    placeholderTextColor: Theme.textDisabled
                    validator: DoubleValidator { bottom: -180; top: 180 }
                    background: Rectangle { color: Theme.surface; radius: Theme.radiusSmall; border.color: Theme.border }
                }
            }

            Button {
                text: "Add Location"
                onClicked: {
                    if (manualLat.text && manualLon.text) {
                        app.addManualLocation(manualName.text, parseFloat(manualLat.text), parseFloat(manualLon.text));
                        manualName.text = "";
                        manualLat.text = "";
                        manualLon.text = "";
                    }
                }

                background: Rectangle {
                    color: parent.hovered ? Theme.accentHover : Theme.accent
                    radius: Theme.radiusSmall
                }
                contentItem: Text {
                    text: parent.text
                    color: Theme.text
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // --- Section 3: Saved locations ---
            Text {
                text: "Saved Locations"
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
                Layout.topMargin: Theme.spacingLarge
            }

            Repeater {
                model: app.locationModel

                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    // Highlight the currently active location
                    color: index === app.settings.activeLocationIndex ? Theme.surfaceAlt : "transparent"
                    radius: Theme.radiusSmall

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium

                        // Click name to switch to this location
                        Text {
                            text: model.name
                            color: Theme.text
                            font.pixelSize: 13
                            Layout.fillWidth: true
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                onClicked: app.setActiveLocation(index)
                            }
                        }

                        // Show coordinates for identification
                        Text {
                            text: model.lat.toFixed(2) + ", " + model.lon.toFixed(2)
                            color: Theme.textDisabled
                            font.pixelSize: 11
                        }

                        // Delete button
                        Button {
                            text: "\u2715"
                            flat: true
                            onClicked: app.removeLocation(index)
                            contentItem: Text {
                                text: parent.text
                                color: Theme.error
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Item {}
                        }
                    }
                }
            }

            // --- Section 4: Weather element toggles ---
            Text {
                text: "Weather Elements"
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
                Layout.topMargin: Theme.spacingLarge
            }

            // Two-column grid of checkboxes.  Keys match Open-Meteo API
            // parameter names, which are also used as settings keys and
            // chart visibility flags -- one name flows through the whole system.
            GridLayout {
                columns: 2
                columnSpacing: Theme.spacingLarge
                rowSpacing: Theme.spacingSmall
                Layout.fillWidth: true

                Repeater {
                    model: [
                        { key: "temperature_2m", label: "Temperature" },
                        { key: "apparent_temperature", label: "Feels Like" },
                        { key: "wind_speed_10m", label: "Wind Speed" },
                        { key: "wind_gusts_10m", label: "Wind Gusts" },
                        { key: "relative_humidity_2m", label: "Humidity" },
                        { key: "cloud_cover", label: "Cloud Cover" },
                        { key: "precipitation_probability", label: "Precip Probability" },
                        { key: "rain", label: "Rain Amounts" },
                        { key: "snowfall", label: "Snowfall" },
                        { key: "snow_depth", label: "Snow Depth" },
                    ]

                    CheckBox {
                        text: modelData.label
                        checked: app.settings.isElementEnabled(modelData.key)
                        onToggled: app.settings.setElementEnabled(modelData.key, checked)

                        contentItem: Text {
                            text: parent.text
                            color: Theme.text
                            font.pixelSize: 13
                            leftPadding: parent.indicator.width + parent.spacing
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            // --- Section 5: Refresh interval ---
            Text {
                text: "Refresh Interval"
                font.pixelSize: 16
                font.bold: true
                color: Theme.text
                Layout.topMargin: Theme.spacingLarge
            }

            RowLayout {
                spacing: Theme.spacingMedium

                Repeater {
                    model: [15, 30, 60]

                    Button {
                        text: modelData + " min"
                        flat: true
                        checked: app.settings.refreshIntervalMinutes === modelData
                        onClicked: app.settings.refreshIntervalMinutes = modelData

                        background: Rectangle {
                            color: parent.checked ? Theme.accent : Theme.surface
                            radius: Theme.radiusSmall
                            border.color: Theme.border
                        }
                        contentItem: Text {
                            text: parent.text
                            color: Theme.text
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Item { height: Theme.spacingXLarge }
        }
    }
}
