import QtQuick
import QtQuick.Layouts
import "../theme"

// Top summary bar showing current weather at a glance.
// Reads from app.currentConditions which is populated from hourly[0].
// Layout: [icon] [temp + description] [feels/humidity/wind] [spacer] [date/time | precip/cloud]

Rectangle {
    id: root
    color: Theme.surface
    radius: Theme.radiusMedium
    // Taller than the legacy 80px to accommodate 2x larger fonts
    height: 140

    property var conditions: app.currentConditions
    property string currentDateTime: ""

    // Update the displayed date/time every minute
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date();
            var days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
            var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
            var h = now.getHours();
            var ampm = h >= 12 ? "PM" : "AM";
            h = h % 12 || 12;
            var min = now.getMinutes().toString().padStart(2, "0");
            root.currentDateTime = days[now.getDay()] + ", "
                + months[now.getMonth()] + " " + now.getDate()
                + "  \u2022  " + h + ":" + min + " " + ampm;
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingLarge

        WeatherIcon {
            weatherCode: conditions ? conditions.weatherCode : 0
            // Larger icon to match 2x font scale
            size: 80
        }

        // Primary: temperature + WMO description
        ColumnLayout {
            spacing: 4

            Text {
                text: conditions ? Math.round(conditions.temperature) + "\u00b0F" : "--"
                // 2x the legacy 28px display size
                font.pixelSize: Theme.fontDisplay
                font.bold: true
                color: Theme.text
            }
            Text {
                text: conditions ? conditions.description : ""
                // 2x the legacy 13px body size
                font.pixelSize: Theme.fontBody
                color: Theme.textSecondary
            }
        }

        // Secondary: feels-like, humidity, wind
        ColumnLayout {
            spacing: 4
            Layout.leftMargin: Theme.spacingLarge

            Text {
                text: conditions ? "Feels like " + Math.round(conditions.feelsLike) + "\u00b0F" : ""
                // 2x the legacy 12px secondary size
                font.pixelSize: Theme.fontSecondary
                color: Theme.textSecondary
            }
            Text {
                text: conditions ? "Humidity " + conditions.humidity + "%" : ""
                font.pixelSize: Theme.fontSecondary
                color: Theme.textSecondary
            }
            Text {
                text: conditions ? "Wind " + Math.round(conditions.windSpeed) + " mph, gusts " + Math.round(conditions.windGusts) + " mph" : ""
                font.pixelSize: Theme.fontSecondary
                color: Theme.textSecondary
            }
        }

        Item { Layout.fillWidth: true }

        // Right side: date/time + precipitation and cloud cover
        ColumnLayout {
            spacing: 4
            Layout.alignment: Qt.AlignRight

            Text {
                text: root.currentDateTime
                font.pixelSize: Theme.fontSecondary
                font.bold: true
                color: Theme.text
                horizontalAlignment: Text.AlignRight
            }

            Text {
                text: conditions ? "Precip " + conditions.precipProbability + "%" : ""
                font.pixelSize: Theme.fontSecondary
                color: Theme.textSecondary
                horizontalAlignment: Text.AlignRight
            }
            Text {
                text: conditions ? "Cloud " + conditions.cloudCover + "%" : ""
                font.pixelSize: Theme.fontSecondary
                color: Theme.textSecondary
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
