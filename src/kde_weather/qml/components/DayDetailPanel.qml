import QtQuick
import QtQuick.Layouts
import "../theme"

// Expanded NWS detail for the day selected in the 7-Day tab.
// Reads app.dayDetail (loading / error / available / periods / alerts) and
// renders, top to bottom: the date heading, a transient state line, alert
// boxes (colored by severity), and the day + night narrative paragraphs.
ColumnLayout {
    id: panel
    spacing: Theme.spacingMedium

    // Selected date, e.g. "Wednesday, June 17"
    Text {
        text: {
            var ds = app.dayDetail.selectedDate;
            if (!ds) return "";
            var d = new Date(ds + "T00:00:00");
            var days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
            var months = ["January","February","March","April","May","June",
                          "July","August","September","October","November","December"];
            return days[d.getDay()] + ", " + months[d.getMonth()] + " " + d.getDate();
        }
        font.pixelSize: Theme.fontTitle
        font.bold: true
        color: Theme.text
    }

    // Loading
    Text {
        visible: app.dayDetail.loading
        text: "Loading National Weather Service forecast…"
        font.pixelSize: Theme.fontBody
        color: Theme.textSecondary
    }

    // Non-US / uncovered point
    Text {
        visible: !app.dayDetail.loading && !app.dayDetail.available && app.dayDetail.error === ""
        text: "Detailed National Weather Service forecasts are only available for US locations."
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        font.pixelSize: Theme.fontBody
        color: Theme.textSecondary
    }

    // Network error (re-click the day to retry)
    Text {
        visible: app.dayDetail.error !== ""
        text: "Couldn't load forecast: " + app.dayDetail.error + "  (click the day again to retry)"
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        font.pixelSize: Theme.fontBody
        color: Theme.error
    }

    // Alerts -- severe/extreme in red, everything else amber
    Repeater {
        model: app.dayDetail.alerts
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            color: Theme.surface
            radius: Theme.radiusMedium
            border.width: 2
            border.color: (modelData.severity === "Severe" || modelData.severity === "Extreme")
                          ? Theme.error : Theme.warning
            implicitHeight: alertCol.implicitHeight + 2 * Theme.spacingMedium

            ColumnLayout {
                id: alertCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingMedium
                spacing: Theme.spacingSmall

                Text {
                    text: modelData.event
                          + (modelData.expiresText ? "  —  " + modelData.expiresText : "")
                    font.pixelSize: Theme.fontBody
                    font.bold: true
                    color: (modelData.severity === "Severe" || modelData.severity === "Extreme")
                           ? Theme.error : Theme.warning
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Text {
                    visible: modelData.text !== ""
                    text: modelData.text
                    font.pixelSize: Theme.fontSecondary
                    color: Theme.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
    }

    // Day + night narrative paragraphs
    Repeater {
        model: app.dayDetail.periods
        ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: modelData.name
                font.pixelSize: Theme.fontBody
                font.bold: true
                color: Theme.accent
            }
            Text {
                text: modelData.text
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.pixelSize: Theme.fontBody
                color: Theme.text
            }
        }
    }

    // US, available, no alerts and no periods for this (far-out) day
    Text {
        visible: !app.dayDetail.loading && app.dayDetail.available
                 && app.dayDetail.error === ""
                 && app.dayDetail.selectedDate !== ""
                 && app.dayDetail.periods.length === 0
                 && app.dayDetail.alerts.length === 0
        text: "No detailed forecast available for this day."
        font.pixelSize: Theme.fontBody
        color: Theme.textSecondary
    }
}
