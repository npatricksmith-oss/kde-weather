import QtQuick
import QtQuick.Layouts
import "../theme"

// Top summary bar showing current weather at a glance.
// Reads from app.currentConditions which is populated from hourly[0].
// Layout: [icon] [temp + description] [feels/humidity/wind] [spacer] [precip/cloud]

Rectangle {
    id: root
    color: Theme.surface
    radius: Theme.radiusMedium
    height: 80

    property var conditions: app.currentConditions

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingLarge

        WeatherIcon {
            weatherCode: conditions ? conditions.weatherCode : 0
            size: 48
        }

        // Primary: temperature + WMO description
        ColumnLayout {
            spacing: 2

            Text {
                text: conditions ? Math.round(conditions.temperature) + "\u00b0F" : "--"
                font.pixelSize: 28
                font.bold: true
                color: Theme.text
            }
            Text {
                text: conditions ? conditions.description : ""
                font.pixelSize: 13
                color: Theme.textSecondary
            }
        }

        // Secondary: feels-like, humidity, wind
        ColumnLayout {
            spacing: 2
            Layout.leftMargin: Theme.spacingLarge

            Text {
                text: conditions ? "Feels like " + Math.round(conditions.feelsLike) + "\u00b0F" : ""
                font.pixelSize: 12
                color: Theme.textSecondary
            }
            Text {
                text: conditions ? "Humidity " + conditions.humidity + "%" : ""
                font.pixelSize: 12
                color: Theme.textSecondary
            }
            Text {
                text: conditions ? "Wind " + Math.round(conditions.windSpeed) + " mph, gusts " + Math.round(conditions.windGusts) + " mph" : ""
                font.pixelSize: 12
                color: Theme.textSecondary
            }
        }

        Item { Layout.fillWidth: true }

        // Right side: precipitation and cloud cover
        ColumnLayout {
            spacing: 2
            Layout.alignment: Qt.AlignRight

            Text {
                text: conditions ? "Precip " + conditions.precipProbability + "%" : ""
                font.pixelSize: 12
                color: Theme.textSecondary
                horizontalAlignment: Text.AlignRight
            }
            Text {
                text: conditions ? "Cloud " + conditions.cloudCover + "%" : ""
                font.pixelSize: 12
                color: Theme.textSecondary
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
