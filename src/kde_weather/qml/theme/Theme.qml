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

    // Chart line colors -- chosen to be visually distinct from each other
    // and readable against the dark surface background
    readonly property color chartTemp: "#e74c3c"         // Red -- hot
    readonly property color chartFeelsLike: "#e67e22"    // Orange -- warm
    readonly property color chartHumidity: "#3498db"     // Blue -- water
    readonly property color chartPrecipProb: "#2ecc71"   // Green
    readonly property color chartRain: "#1abc9c"         // Teal
    readonly property color chartSnowfall: "#9b59b6"     // Purple -- cold
    readonly property color chartSnowDepth: "#8e44ad"    // Dark purple
    readonly property color chartCloudCover: "#95a5a6"   // Gray -- sky
    readonly property color chartWindSpeed: "#f39c12"    // Yellow
    readonly property color chartWindGusts: "#d35400"    // Dark orange

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
