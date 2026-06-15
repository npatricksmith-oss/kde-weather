import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "../components"

// 7-Day forecast: a horizontally-scrollable row of DayCard components, with a
// detail panel below that expands when a day is clicked (NWS narrative + alerts).
// The whole tab scrolls vertically so a long narrative is reachable.
ScrollView {
    id: root
    contentWidth: availableWidth

    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.spacingLarge

        // Horizontally-scrollable row of day cards.
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: row.height
            contentWidth: row.width
            contentHeight: row.height
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            RowLayout {
                id: row
                spacing: Theme.spacingMedium

                Repeater {
                    model: app.dailyModel

                    DayCard {
                        // Role names come from DailyModel.roleNames()
                        date: model.date || ""
                        tempMax: model.tempMax || 0
                        tempMin: model.tempMin || 0
                        precipProb: model.precipProbMax || 0
                        windMax: model.windMax || 0
                        weatherCode: model.weatherCode || 0
                        sunrise: model.sunrise || ""
                        sunset: model.sunset || ""
                        selected: app.dayDetail.selectedDate === (model.date || "")
                        onClicked: app.selectDay(model.date || "")
                    }
                }
            }
        }

        // Expanded NWS detail for the selected day.
        DayDetailPanel {
            Layout.fillWidth: true
            visible: app.dayDetail.selectedDate !== ""
        }
    }
}
