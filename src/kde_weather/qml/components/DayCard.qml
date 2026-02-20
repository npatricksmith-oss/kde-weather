import QtQuick
import QtQuick.Layouts
import "../theme"

// A single day's forecast summary, used in the 7-Day tab.
// Shows day name, weather icon, high/low temps, precip probability bar, wind.
// The precip bar is a visual fill-bar (0-100%) -- more intuitive than a number.

Rectangle {
    id: root
    color: Theme.card
    radius: Theme.radiusMedium
    width: 140
    height: 200

    property string date: ""
    property real tempMax: 0
    property real tempMin: 0
    property int precipProb: 0
    property real windMax: 0
    property int weatherCode: 0
    property string sunrise: ""
    property string sunset: ""

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        // Format "2026-02-19" as "Wed Feb 19"
        Text {
            text: {
                if (!root.date) return "";
                var d = new Date(root.date + "T00:00:00");
                var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
                var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
                return days[d.getDay()] + " " + months[d.getMonth()] + " " + d.getDate();
            }
            font.pixelSize: 13
            font.bold: true
            color: Theme.text
            Layout.alignment: Qt.AlignHCenter
        }

        WeatherIcon {
            weatherCode: root.weatherCode
            size: 40
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: Math.round(root.tempMax) + "\u00b0 / " + Math.round(root.tempMin) + "\u00b0"
            font.pixelSize: 16
            font.bold: true
            color: Theme.text
            Layout.alignment: Qt.AlignHCenter
        }

        // Precipitation probability as text + fill bar
        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            Text {
                text: root.precipProb + "% precip"
                font.pixelSize: 11
                color: Theme.textSecondary
                Layout.alignment: Qt.AlignHCenter
            }

            // Background track
            Rectangle {
                Layout.fillWidth: true
                height: 4
                radius: 2
                color: Theme.border

                // Fill indicator -- width scales with probability
                Rectangle {
                    width: parent.width * (root.precipProb / 100)
                    height: parent.height
                    radius: 2
                    color: Theme.chartPrecipProb
                }
            }
        }

        Text {
            text: "Wind " + Math.round(root.windMax) + " mph"
            font.pixelSize: 11
            color: Theme.textSecondary
            Layout.alignment: Qt.AlignHCenter
        }

        Item { Layout.fillHeight: true }
    }
}
