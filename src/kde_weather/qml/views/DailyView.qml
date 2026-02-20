import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "../components"

// 7-day forecast displayed as a horizontal row of DayCard components.
// Each card is rendered by a Repeater bound to app.dailyModel.
// The row is scrollable horizontally if the window is narrow.

ScrollView {
    id: root
    contentWidth: availableWidth

    Flickable {
        contentWidth: row.width
        contentHeight: row.height

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
                }
            }
        }
    }
}
