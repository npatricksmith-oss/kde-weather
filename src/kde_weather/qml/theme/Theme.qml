pragma Singleton
import QtQuick

// Centralized color and spacing constants for the Breeze Dark theme.
//
// Using a QML singleton rather than inline colors because:
//   1. Single place to update if the palette changes
//   2. Chart colors need to be distinct and coordinated -- easier to
//      see them all in one place than scattered across 10 chart instances
//   3. QML singletons are resolved at compile time, no runtime cost
//
// The surface/surfaceAlt/card hierarchy follows Material Design's
// "surface tint" concept: each layer is slightly lighter to convey
// visual elevation without drop shadows.

QtObject {
    // Background layers (darkest to lightest)
    readonly property color background: "#141618"   // Window bg
    readonly property color surface: "#1b1e20"      // Cards, toolbar
    readonly property color surfaceAlt: "#232629"    // Hover states, active tab
    readonly property color card: "#2a2e32"          // Elevated cards (DayCard)
    readonly property color border: "#3b4045"        // Dividers, input borders

    // Text hierarchy
    readonly property color text: "#fcfcfc"          // Primary text
    readonly property color textSecondary: "#a0a4a8" // Labels, secondary info
    readonly property color textDisabled: "#6e7175"  // Disabled/placeholder

    // Accent and status
    readonly property color accent: "#3daee9"        // KDE Breeze accent blue
    readonly property color accentHover: "#4dc0ff"   // Lighter accent for hover
    readonly property color error: "#da4453"         // Error text, delete buttons
    readonly property color success: "#27ae60"       // Unused currently, reserved

    // Chart line colors -- natural weather associations, no color reused across types.
    // Temperature: red for temp, amber for feels-like.  Both warm tones but
    // far enough apart in hue/brightness to be immediately distinguishable.
    readonly property color chartTemp: "#ef5350"         // Warm red -- temperature
    readonly property color chartFeelsLike: "#ffb300"    // Amber/gold -- body warmth (was orange #ff7043, too close to red)
    // Wind: medium purple for wind speed, bright orchid for gusts.
    // Same hue family but drastically different values so a quick glance tells them apart.
    readonly property color chartWindSpeed: "#9c27b0"    // Medium purple -- wind
    readonly property color chartWindGusts: "#e040fb"    // Bright orchid/magenta -- gusts (was dark purple #6a1b9a, too similar)
    // Precipitation: blues (rain = deep, probability = medium)
    readonly property color chartPrecipProb: "#1e88e5"   // Medium blue -- rain chance
    readonly property color chartRain: "#1565c0"         // Deep blue -- actual rain
    // Snow: near-white and light gray (natural snow colors)
    readonly property color chartSnowfall: "#e0f4ff"     // Near-white light blue -- falling snow
    readonly property color chartSnowDepth: "#b0bec5"    // Blue-gray -- snow on ground
    // Humidity: greens (water vapor in air)
    readonly property color chartHumidity: "#43a047"     // Green -- moisture
    // Cloud: blue-gray (sky with clouds)
    readonly property color chartCloudCover: "#78909c"   // Muted blue-gray -- clouds

    // Font sizes -- all 2x the legacy base sizes so the app reads comfortably
    // at typical viewing distances on a 14" 2560x1600 display.
    readonly property int fontAxisLabel: 18   // Chart axis tick labels (was 9)
    readonly property int fontLegend: 20      // Chart legend text (was 10)
    readonly property int fontSecondary: 22   // Toolbar status text (was 11)
    readonly property int fontBody: 26        // Primary UI text, tabs, combobox (was 13)
    readonly property int fontTitle: 32       // Section/panel titles (was 16)
    readonly property int fontDisplay: 56     // Temperature large display (was 28)

    // Corner radii
    readonly property int radiusSmall: 4
    readonly property int radiusMedium: 8
    readonly property int radiusLarge: 12

    // Layout spacing
    readonly property int spacingSmall: 4
    readonly property int spacingMedium: 8
    readonly property int spacingLarge: 16
    readonly property int spacingXLarge: 24
}
