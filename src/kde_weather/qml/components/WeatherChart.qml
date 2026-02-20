import QtQuick
import QtQuick.Layouts
import QtCharts
import "../theme"

// Reusable chart panel for one weather element (e.g. Temperature, Wind).
//
// Receives data as [{x: ms_timestamp, y: value}, ...] arrays via the
// seriesData and secondaryData properties.  When these change,
// updateChart() imperatively clears and repopulates the SplineSeries.
//
// We use SplineSeries (smooth curves) instead of LineSeries for a
// polished look.  The y-axis snaps to clean intervals so labels land on
// round numbers (10°F steps, 10% steps, etc.), and labelsFormat: "%d"
// suppresses decimal points on all y-axis tick labels.
//
// X-axis strategy: the axis min is snapped back to the previous 6-hour
// local-time boundary (midnight, 6am, noon, 6pm) before the first data
// point.  tickCount is computed so every subsequent tick also falls on a
// 6-hour boundary.  This means the first data point (current hour) sits
// slightly right of the axis origin, and all visible tick labels are clean
// clock marks like "Fri 6 PM" rather than "Fri 9 AM", "Fri 3 PM", etc.
//
// Day shading: alternating calendar days get a faint white tint so the
// viewer can see day transitions without the shading distracting from the
// data.  Shading rectangles are positioned using fractional math against
// the chart's plotArea rect, which auto-updates on resize.
//
// clampMin: when set, prevents the y-axis from dropping below that value
// (e.g. clampMin: 0 for wind speed so the axis never goes negative).

Rectangle {
    id: root
    color: Theme.surface
    radius: Theme.radiusMedium
    // Taller than the legacy 220px to accommodate 2x larger font labels
    height: 320

    property string title: ""
    property string unit: ""
    property color lineColor: Theme.accent
    property var seriesData: []          // Primary: [{x: ms_timestamp, y}, ...]
    property string secondaryTitle: ""
    property color secondaryColor: "transparent"
    property var secondaryData: []       // Optional overlay series
    property real clampMin: -1e9        // Floor for y-axis min (use 0 for wind)

    // Computed by updateChart() and consumed by the day-shading Repeater
    property var dayBands: []
    property real xAxisMinMs: 0
    property real xAxisMaxMs: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        spacing: 0

        Text {
            text: root.title + (root.unit ? " (" + root.unit + ")" : "")
            // 2x the legacy 13px title size
            font.pixelSize: Theme.fontBody
            font.bold: true
            color: Theme.text
        }

        // Wrapper Item stacks the day-shading layer behind the ChartView.
        // ChartView uses backgroundColor: "transparent" so the shading
        // rectangles positioned beneath it are visible through the plot area.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Day-alternating shading bands.  Positioned and clipped to the
            // chart's plotArea so they only cover the data region, not the
            // axis label gutters.  Declared before ChartView so it renders
            // underneath (later siblings render on top in QML).
            Item {
                id: shadingLayer
                // Bind to chart.plotArea so this repositions on every resize
                x: chart.plotArea.x
                y: chart.plotArea.y
                width: chart.plotArea.width
                height: chart.plotArea.height
                clip: true

                Repeater {
                    model: root.dayBands
                    Rectangle {
                        // Fractional x/width: (band offset within total span) * layer width
                        property real span: root.xAxisMaxMs - root.xAxisMinMs
                        x: span > 0 ? ((modelData.startMs - root.xAxisMinMs) / span) * shadingLayer.width : 0
                        y: 0
                        width: span > 0 ? ((modelData.endMs - modelData.startMs) / span) * shadingLayer.width : 0
                        height: shadingLayer.height
                        // Even days get a faint white tint; odd days are fully transparent.
                        // ~4% white opacity is subtle enough not to obscure grid lines.
                        color: modelData.even ? "#0affffff" : "transparent"
                    }
                }
            }

            ChartView {
                id: chart
                anchors.fill: parent
                antialiasing: true
                backgroundColor: "transparent"
                legend.visible: root.secondaryData.length > 0
                legend.labelColor: Theme.textSecondary
                // 2x the legacy 10px legend size
                legend.font.pixelSize: Theme.fontLegend
                margins { top: 0; bottom: 0; left: 0; right: 0 }

                // X axis: wall-clock labels showing day + time ("Mon 9 PM").
                // min/max and tickCount are set dynamically in updateChart()
                // so that all ticks fall on 6-hour local-time boundaries.
                DateTimeAxis {
                    id: xAxis
                    format: "ddd h AP"
                    labelsColor: Theme.textSecondary
                    // 2x the legacy 9px axis label size
                    labelsFont.pixelSize: Theme.fontAxisLabel
                    gridLineColor: Theme.border
                    lineVisible: false
                }

                // Y axis: auto-scaled in updateChart().
                // labelFormat: "%d" suppresses decimal points (e.g. "35" not "35.0").
                ValuesAxis {
                    id: yAxis
                    labelFormat: "%d"
                    labelsColor: Theme.textSecondary
                    // 2x the legacy 9px axis label size
                    labelsFont.pixelSize: Theme.fontAxisLabel
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
    }

    onSeriesDataChanged: updateChart()
    onSecondaryDataChanged: updateChart()

    // Return a "nice" step size for a given data range so y-axis labels
    // land on round numbers (e.g. 10°F, 5 mph, 10% rather than 7.3, 4.1, 8.6).
    function niceInterval(range) {
        if (range <= 0) return 1;
        var raw = range / 5;   // target ~5 tick intervals
        var exp = Math.floor(Math.log(raw) / Math.LN10);
        var frac = raw / Math.pow(10, exp);
        var nice = frac < 1.5 ? 1 : frac < 3 ? 2 : frac < 7 ? 5 : 10;
        return nice * Math.pow(10, exp);
    }

    function updateChart() {
        // Clear existing points and rebuild from scratch.
        // QtCharts doesn't support efficient partial updates, so full
        // replacement is the standard approach for data refreshes.
        mainSeries.clear();
        secondarySeries.clear();

        if (seriesData.length === 0) return;

        // Populate series and collect all Y values for axis range computation
        var allY = [];
        for (var i = 0; i < seriesData.length; i++) {
            mainSeries.append(seriesData[i].x, seriesData[i].y);
            allY.push(seriesData[i].y);
        }
        for (var j = 0; j < secondaryData.length; j++) {
            secondarySeries.append(secondaryData[j].x, secondaryData[j].y);
            allY.push(secondaryData[j].y);
        }

        // Snap Y axis to clean intervals so labels hit round numbers
        var rawMin = Math.min.apply(null, allY);
        var rawMax = Math.max.apply(null, allY);
        var interval = niceInterval(rawMax - rawMin);
        var axisMin = Math.floor(rawMin / interval) * interval;
        var axisMax = Math.ceil(rawMax / interval) * interval;
        // Ensure at least one interval of headroom on each side
        if (axisMin === axisMax) { axisMin -= interval; axisMax += interval; }
        // Apply optional floor (e.g. wind speed should never show negative)
        axisMin = Math.max(axisMin, root.clampMin);
        yAxis.min = axisMin;
        yAxis.max = axisMax;
        yAxis.tickCount = Math.round((axisMax - axisMin) / interval) + 1;

        // X-axis: snap the axis origin back to the previous 6-hour local-time
        // boundary (midnight, 6am, noon, 6pm) before the first data point.
        // This ensures every subsequent tick mark also lands on a 6h boundary,
        // giving labels like "Fri 6 PM" / "Sat 12 AM" rather than "Fri 9 AM" /
        // "Fri 3 PM" (which would result from distributing ticks uniformly from
        // an arbitrary start time).
        var dataStartMs = seriesData[0].x;
        var dataEndMs = seriesData[seriesData.length - 1].x;

        var startDate = new Date(dataStartMs);
        var localHour = startDate.getHours();
        // Round down to the nearest multiple of 6 hours in local time
        var prevBoundaryHour = Math.floor(localHour / 6) * 6;
        var prevSnap = new Date(startDate);
        prevSnap.setHours(prevBoundaryHour, 0, 0, 0);
        var prevSnapMs = prevSnap.getTime();

        var sixHMs = 6 * 3600 * 1000;
        // Number of 6h intervals from prevSnap forward past the last data point.
        // Math.ceil ensures the final tick is always at or beyond the last data.
        var numIntervals = Math.ceil((dataEndMs - prevSnapMs) / sixHMs);

        // Snap the axis max to the next 6h boundary so every tick falls on an
        // exact 6-hour clock mark (midnight, 6 AM, noon, 6 PM).
        // Without this, DateTimeAxis distributes ticks evenly between prevSnap
        // and the raw dataEndMs (which is not on a 6h boundary), producing
        // irregular intervals like 5h 34m instead of a clean 6h.
        var axisMaxMs = prevSnapMs + numIntervals * sixHMs;

        xAxis.min = prevSnap;
        xAxis.max = new Date(axisMaxMs);
        xAxis.tickCount = numIntervals + 1;

        // Compute calendar-day bands for the alternating background shading.
        // Each band covers one calendar day within the axis range; alternating
        // bands get a faint white tint so day transitions are subtly visible.
        // Use axisMaxMs (the snapped boundary) so shading covers the full axis.
        var bands = [];
        var axisStartMs = prevSnapMs;
        var axisEndMs = axisMaxMs;

        // Find the first calendar midnight after the axis start
        var firstMidnight = new Date(prevSnap);
        firstMidnight.setHours(24, 0, 0, 0);
        var firstMidnightMs = firstMidnight.getTime();

        var dayIdx = 0;
        if (firstMidnightMs >= axisEndMs) {
            // All data falls within a single calendar day
            bands.push({ startMs: axisStartMs, endMs: axisEndMs, even: true });
        } else {
            // First partial day (axis start → first midnight)
            bands.push({ startMs: axisStartMs, endMs: firstMidnightMs, even: true });
            dayIdx++;
            var bandStart = firstMidnightMs;
            var msPerDay = 24 * 3600 * 1000;
            while (bandStart < axisEndMs) {
                var bandEnd = Math.min(bandStart + msPerDay, axisEndMs);
                bands.push({ startMs: bandStart, endMs: bandEnd, even: dayIdx % 2 === 0 });
                dayIdx++;
                bandStart += msPerDay;
            }
        }

        root.dayBands = bands;
        root.xAxisMinMs = axisStartMs;   // prevSnapMs (6h boundary before data start)
        root.xAxisMaxMs = axisEndMs;     // axisMaxMs  (6h boundary after data end)
    }
}
