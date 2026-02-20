import QtQuick
import QtQuick.Layouts
import QtCharts
import "../theme"

// Reusable chart panel for one weather element (e.g. Temperature, Wind).
//
// Receives data as [{x: hourIndex, y: value}, ...] arrays via the
// seriesData and secondaryData properties.  When these change,
// updateChart() imperatively clears and repopulates the SplineSeries.
//
// We use SplineSeries (smooth curves) instead of LineSeries for a
// polished look.  The y-axis auto-scales with 10% padding so data
// fills the chart area nicely.
//
// Supports an optional secondary series (e.g. "Feels Like" overlaid
// on Temperature, or "Gusts" overlaid on Wind Speed).  The legend
// only shows when there's a secondary series.

Rectangle {
    id: root
    color: Theme.surface
    radius: Theme.radiusMedium
    height: 220

    property string title: ""
    property string unit: ""
    property color lineColor: Theme.accent
    property var seriesData: []          // Primary: [{x, y}, ...]
    property var timeLabels: []          // ISO time strings for axis
    property string secondaryTitle: ""
    property color secondaryColor: "transparent"
    property var secondaryData: []       // Optional overlay series

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        spacing: 0

        Text {
            text: root.title + (root.unit ? " (" + root.unit + ")" : "")
            font.pixelSize: 13
            font.bold: true
            color: Theme.text
        }

        ChartView {
            id: chart
            Layout.fillWidth: true
            Layout.fillHeight: true
            antialiasing: true
            backgroundColor: "transparent"
            legend.visible: root.secondaryData.length > 0
            legend.labelColor: Theme.textSecondary
            legend.font.pixelSize: 10
            margins { top: 0; bottom: 0; left: 0; right: 0 }

            // X axis: hour index (0-47)
            ValuesAxis {
                id: xAxis
                min: 0
                max: Math.max(root.seriesData.length - 1, 1)
                tickCount: Math.min(root.seriesData.length, 9)
                labelsColor: Theme.textSecondary
                labelsFont.pixelSize: 9
                gridLineColor: Theme.border
                lineVisible: false
            }

            // Y axis: auto-scaled in updateChart()
            ValuesAxis {
                id: yAxis
                labelsColor: Theme.textSecondary
                labelsFont.pixelSize: 9
                gridLineColor: Theme.border
                lineVisible: false
            }

            SplineSeries {
                id: mainSeries
                name: root.title
                axisX: xAxis
                axisY: yAxis
                color: root.lineColor
                width: 2
            }

            SplineSeries {
                id: secondarySeries
                name: root.secondaryTitle
                axisX: xAxis
                axisY: yAxis
                color: root.secondaryColor
                width: 2
                visible: root.secondaryData.length > 0
            }
        }
    }

    onSeriesDataChanged: updateChart()
    onSecondaryDataChanged: updateChart()

    function updateChart() {
        // Clear existing points and rebuild from scratch.
        // QtCharts doesn't support efficient partial updates, so full
        // replacement is the standard approach for data refreshes.
        mainSeries.clear();
        secondarySeries.clear();

        if (seriesData.length === 0) return;

        // Collect all Y values to compute axis range
        var allY = [];
        for (var i = 0; i < seriesData.length; i++) {
            mainSeries.append(seriesData[i].x, seriesData[i].y);
            allY.push(seriesData[i].y);
        }
        for (var j = 0; j < secondaryData.length; j++) {
            secondarySeries.append(secondaryData[j].x, secondaryData[j].y);
            allY.push(secondaryData[j].y);
        }

        // Auto-scale Y axis with 10% padding (min 1 unit) so data
        // doesn't clip against the top/bottom edges
        var minY = Math.min.apply(null, allY);
        var maxY = Math.max.apply(null, allY);
        var pad = Math.max((maxY - minY) * 0.1, 1);
        yAxis.min = Math.floor(minY - pad);
        yAxis.max = Math.ceil(maxY + pad);
        xAxis.max = Math.max(seriesData.length - 1, 1);
    }
}
