import QtQuick

// Maps WMO weather codes to emoji glyphs.
//
// We use Unicode emoji instead of Breeze icon theme SVGs because:
//   1. No dependency on icon theme being installed
//   2. Works outside KDE Plasma sessions
//   3. Renders at any size without pixelation
//
// WMO codes are not contiguous -- they jump from 3 to 45, from 77 to 80,
// etc.  The if-chain uses <= ranges to bucket codes into weather categories.
// Full WMO code table: https://www.nodc.noaa.gov/archive/arc0021/0002199/1.1/data/0-data/HTML/WMO-CODE/WMO4677.HTM
//
// font.family is set to "Noto Color Emoji" so the glyphs render with their
// natural colors (yellow sun, white clouds, blue rain, etc.) rather than as
// monochrome black glyphs.  On Arch Linux this requires the noto-fonts-emoji
// package (installed by install.sh).

Item {
    id: root
    property int weatherCode: 0
    property int size: 32

    width: size
    height: size

    // Semi-transparent circle behind emoji so glyphs remain visible on any
    // background color (dark surfaces can make some emoji near-invisible).
    Rectangle {
        anchors.centerIn: parent
        width: root.size * 1.15
        height: root.size * 1.15
        radius: width / 2
        color: "#28ffffff"
        border.color: "#18ffffff"
        border.width: 1
    }

    Text {
        anchors.centerIn: parent
        // Noto Color Emoji forces the OS emoji font to render in full color.
        // Without this, Qt may use a monochrome system font for the glyphs.
        font.family: "Noto Color Emoji"
        font.pixelSize: root.size * 0.75
        text: {
            var code = root.weatherCode;
            if (code === 0) return "\u2600";        // Clear sky - sun
            if (code <= 2) return "\u26c5";          // Partly cloudy
            if (code === 3) return "\u2601";          // Overcast
            if (code <= 48) return "\ud83c\udf2b";    // Fog (codes 45, 48)
            if (code <= 57) return "\ud83c\udf26";    // Drizzle (51-57)
            if (code <= 67) return "\ud83c\udf27";    // Rain (61-67)
            if (code <= 77) return "\ud83c\udf28";    // Snow (71-77)
            if (code <= 82) return "\ud83c\udf26";    // Rain showers (80-82)
            if (code <= 86) return "\ud83c\udf28";    // Snow showers (85-86)
            if (code >= 95) return "\u26c8";          // Thunderstorm (95-99)
            return "\u2601";
        }
    }
}
