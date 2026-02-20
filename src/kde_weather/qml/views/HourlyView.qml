import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "../components"

// Scrollable stack of hourly weather charts (one per enabled element).
//
// The central challenge here is reactivity: QML declarative bindings can't
// detect when hourlyModel.seriesData("temperature") would return new data
// because it's an imperative Slot call, not a property.  We solve this with
// the dataVersion pattern:
//
//   1. Python's HourlyModel bumps dataVersion after each update()
//   2. QML binds to hourlyModel.dataVersion (a Q_PROPERTY with notify)
//   3. onDataVersionChanged triggers refreshCharts() which imperatively
//      pushes fresh data into each chart's seriesData property
//   4. WeatherChart reacts to onSeriesDataChanged and redraws
//
// Charts that share related data (e.g. Temperature + Feels Like) are
// combined into a single chart with primary + secondary series.  If the
// primary is disabled but the secondary is on, a standalone chart appears.
//
// Keyboard scrolling: Up/Down arrow keys scroll the view when it has focus.
// forceActiveFocus() is called from main.qml when the hourly tab is selected.

ScrollView {
    id: root

    property var hourlyModel: app.hourlyModel
    property var enabledElements: app.settings.enabledElements
    // Tracks model data freshness -- see module comment above
    property int dataVersion: hourlyModel.dataVersion

    contentWidth: availableWidth

    // One "chart page" = WeatherChart.height (320) + ColumnLayout spacing (8).
    // Scrolling by exactly this amount advances or retreats by one full panel,
    // so the chart below/above lands flush at the top of the viewport.
    readonly property int chartPageHeight: 328   // 320 chart + 8 spacing

    // Accept keyboard focus so Up/Down arrows scroll the chart stack.
    // main.qml calls forceActiveFocus() on this view when the hourly tab
    // is selected, ensuring arrows work immediately after tab switch.
    focus: true
    Keys.onUpPressed: {
        // Scroll up by one full chart panel, clamped to the top
        contentItem.contentY = Math.max(0, contentItem.contentY - chartPageHeight)
    }
    Keys.onDownPressed: {
        // Scroll down by one full chart panel, clamped to the bottom
        var maxY = contentItem.contentHeight - height
        contentItem.contentY = Math.min(Math.max(0, maxY), contentItem.contentY + chartPageHeight)
    }

    function refreshCharts() {
        tempChart.seriesData = hourlyModel.seriesData("temperature");
        tempChart.secondaryData = hourlyModel.seriesData("apparentTemperature");
        feelsLikeChart.seriesData = hourlyModel.seriesData("apparentTemperature");
        windChart.seriesData = hourlyModel.seriesData("windSpeed");
        windChart.secondaryData = hourlyModel.seriesData("windGusts");
        gustChart.seriesData = hourlyModel.seriesData("windGusts");
        humidityChart.seriesData = hourlyModel.seriesData("humidity");
        cloudChart.seriesData = hourlyModel.seriesData("cloudCover");
        precipChart.seriesData = hourlyModel.seriesData("precipProbability");
        rainChart.seriesData = hourlyModel.seriesData("rain");
        snowfallChart.seriesData = hourlyModel.seriesData("snowfall");
        snowDepthChart.seriesData = hourlyModel.seriesData("snowDepth");
    }

    onDataVersionChanged: refreshCharts()

    ColumnLayout {
            id: chartsColumn
            width: root.availableWidth
            spacing: Theme.spacingMedium

            // Temperature + Feels Like combined (when temp is on)
            WeatherChart {
                id: tempChart
                Layout.fillWidth: true
                visible: root.enabledElements["temperature_2m"] || false
                title: "Temperature"
                unit: "\u00b0F"
                lineColor: Theme.chartTemp
                secondaryTitle: "Feels Like"
                secondaryColor: Theme.chartFeelsLike
            }

            // Feels Like standalone (only when temp is off but feels-like is on)
            WeatherChart {
                id: feelsLikeChart
                Layout.fillWidth: true
                visible: !(root.enabledElements["temperature_2m"] || false) && (root.enabledElements["apparent_temperature"] || false)
                title: "Feels Like"
                unit: "\u00b0F"
                lineColor: Theme.chartFeelsLike
            }

            // Wind Speed + Gusts combined
            WeatherChart {
                id: windChart
                Layout.fillWidth: true
                visible: root.enabledElements["wind_speed_10m"] || false
                title: "Wind Speed"
                unit: "mph"
                lineColor: Theme.chartWindSpeed
                secondaryTitle: "Gusts"
                secondaryColor: Theme.chartWindGusts
                clampMin: 0
            }

            // Gusts standalone
            WeatherChart {
                id: gustChart
                Layout.fillWidth: true
                visible: !(root.enabledElements["wind_speed_10m"] || false) && (root.enabledElements["wind_gusts_10m"] || false)
                title: "Wind Gusts"
                unit: "mph"
                lineColor: Theme.chartWindGusts
                clampMin: 0
            }

            WeatherChart {
                id: humidityChart
                Layout.fillWidth: true
                visible: root.enabledElements["relative_humidity_2m"] || false
                title: "Humidity"
                unit: "%"
                lineColor: Theme.chartHumidity
            }

            WeatherChart {
                id: cloudChart
                Layout.fillWidth: true
                visible: root.enabledElements["cloud_cover"] || false
                title: "Cloud Cover"
                unit: "%"
                lineColor: Theme.chartCloudCover
            }

            WeatherChart {
                id: precipChart
                Layout.fillWidth: true
                visible: root.enabledElements["precipitation_probability"] || false
                title: "Precipitation Probability"
                unit: "%"
                lineColor: Theme.chartPrecipProb
            }

            WeatherChart {
                id: rainChart
                Layout.fillWidth: true
                visible: root.enabledElements["rain"] || false
                title: "Rain"
                unit: "in"
                lineColor: Theme.chartRain
            }

            // "Snowfall" = inches of new snow that fell during each hour
            // (a rate from Open-Meteo's snowfall field, converted to inches/hr)
            WeatherChart {
                id: snowfallChart
                Layout.fillWidth: true
                visible: root.enabledElements["snowfall"] || false
                title: "Snowfall \u2014 new snow per hour"
                unit: "in/hr"
                lineColor: Theme.chartSnowfall
            }

            // "Snow Depth" = total inches of snow currently on the ground
            // (the accumulation / snowpack at each hour, Open-Meteo snow_depth)
            WeatherChart {
                id: snowDepthChart
                Layout.fillWidth: true
                visible: root.enabledElements["snow_depth"] || false
                title: "Snow Depth \u2014 total on ground"
                unit: "in"
                lineColor: Theme.chartSnowDepth
            }
        }
}
