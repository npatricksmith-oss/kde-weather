# Issues
- Issues are numbered.
- STATUS: indicates whether the issue has been completed or open (ONLY EDITABLE BY USER, NO AGENT AI to CHANGE)
- Whie STATUS remains OPEN, user will review and add comments to ACTIONS, which AI is instructed to read and to continue to address and iterate fixes. \
- AI AGENT should look for open status, remaning actions, and new issues (numbered).
- AI AGENT should add brief comments to issues regarding actions taken to mitigate issues.

1. Weather Graph tandem colors too similar.
STATUS: CLOSED
PROBLEM: In each graph, the colors are too similar making the tandem graphs hard to decipher. Example, Temp graphs are shades of red and orange which are hard to tell apart on first glance.
EXPECTED: Graphs with two lines have similar but easy to identify lines.
ACTIONS: Fix.
AI COMMENTS: Changed chartFeelsLike from #ff7043 (deep orange, too close to red) to #ffb300 (amber/gold) — same warm family but clearly distinct. Changed chartWindGusts from #6a1b9a (dark purple, nearly indistinguishable from chartWindSpeed #9c27b0) to #e040fb (bright orchid/magenta-purple) — same hue but drastically different brightness. Both changes preserve weather intuition (warm = temp, purple = wind) while making the two series easy to tell apart at a glance. (Theme.qml)

2. 48-hour and 7-day forecast tabs are not visually good.
STATUS: CLOSED
PROBLEM: The tab titles overlap each other.
EXPECTED:
 - Tabs are large enough to accomodate the font size.
 - Tabs are visually identified
 - Active tab is slightly lighter colored than inactive.
 - Tabs remain keyboard activated.
ACTIONS: Fix
AI COMMENTS: Root cause was width: implicitWidth on each TabButton — with a fully-overridden contentItem the implicitWidth is unreliable, causing buttons to overlap or be undersized. Fix: each TabButton is now width: tabBar.width / 2 so both tabs always share the bar equally. TabBar height raised to 54 px (was default 48 px) for comfortable 26 px font. Bar background changed from transparent to Theme.surface so the tab strip is clearly visible. Active tab uses Theme.surfaceAlt (lighter) + an accent-colored 3 px bottom indicator; inactive uses Theme.surface (flush with bar). Keyboard activation unchanged (Qt TabBar handles Tab/arrow keys natively). (main.qml)
 
3. Graph interval start and end times remain incorrect.
STATUS: CLOSED
PROBLEM: The intervals on the 48-hour tab graphs do not have the correct starting and ending time.
EXPECTED:
- The graph intervals should cover 6-hour intervals at 6 or 12 hour marks, depending on the current time. Example 1: if current time is 9:10AM, the graph should start at 6AM, with the remaining intervals beginning at 12PM, 6pm, 12am, 6am, 12pm, etc. Example 2: If current time is 7:35pm, start at 6pm.
ACTIONS: FIX
AI COMMENTS: The axis min (xAxis.min = prevSnap, snapped to prior 6h boundary) was already correct. The bug was in xAxis.max, which was set to the raw data end timestamp (not a 6h boundary). DateTimeAxis distributes ticks evenly between min and max, so a non-6h-boundary max caused uneven intervals (e.g. ~5h 34m instead of 6h). Fix: xAxis.max is now snapped to prevSnapMs + numIntervals * sixHMs — always the next 6h boundary at or after the last data point. All ticks now land on exact midnight/6 AM/noon/6 PM marks. Also updated root.xAxisMaxMs to the snapped value so the day-shading rectangles cover the full axis span correctly. (WeatherChart.qml)

4. Keyboard scrolling in 48-hour tab behavior
STATUS: CLOSED
PROBLEM: keyboard down/up should advance page down or up to next full graph.
ACTIONS: Fix
AI COMMENTS: Previous scroll step was 200 px (arbitrary). WeatherChart panels are 320 px tall with 8 px ColumnLayout spacing between them, so one "chart page" = 328 px. Changed Keys.onUpPressed / Keys.onDownPressed to scroll by chartPageHeight (328) instead of 200. This advances the viewport by exactly one chart panel so the next chart appears flush at the top after one keypress. (HourlyView.qml)

5. Provide a button in the banner (right corner) that will give hazardous weather/advisories etc.
STATUS: OPEN
PROBLEM: A button should exist to access hazardous weather 
6. When window is active, always allow keyboard navigation
8. snowfall/snowdepth graphs may get decimals.
9. Precipitation graph: Probability percentage Line changes colors for different Precipitation patterns. e.g. Line changes from Rain (blue) to snow (white), sleet (purple), freezing rain (pink) where appropriate depending on data. Precipitation amount (inches) shown in scaled bar graphs at appropriate hours with labels at top of each bar. Y-axis of graph remains percentage, and bar graph y values are their own scale not coupled with overall Y-axis.
10. App doesn't start when launched from icon. 
