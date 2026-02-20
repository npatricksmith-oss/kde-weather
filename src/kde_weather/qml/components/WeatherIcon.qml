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

Item {
    id: root
    property int weatherCode: 0
    property int size: 32

    width: size
    height: size

    Text {
        anchors.centerIn: parent
        font.pixelSize: root.size * 0.8
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
