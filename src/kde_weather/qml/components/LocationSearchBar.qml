import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"

// City search with debounced autocomplete.
//
// Typing fires a 400ms debounce timer -- we don't hit the geocoding API
// on every keystroke.  Results appear in a dropdown ListView below the
// input.  Clicking a result calls app.addGeocodedLocation(index) which
// saves the location, clears the search, and triggers a forecast fetch.

ColumnLayout {
    id: root
    spacing: Theme.spacingSmall

    property var geocodeModel: app.geocodeModel

    // Debounce: wait 400ms after last keystroke before querying
    Timer {
        id: debounce
        interval: 400
        onTriggered: app.searchCity(searchField.text)
    }

    TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: "Search city..."
        color: Theme.text
        placeholderTextColor: Theme.textDisabled
        font.pixelSize: 14

        background: Rectangle {
            color: Theme.surface
            radius: Theme.radiusSmall
            border.color: searchField.activeFocus ? Theme.accent : Theme.border
            border.width: 1
        }

        onTextChanged: {
            if (text.length >= 2) {
                debounce.restart();
            } else {
                debounce.stop();
            }
        }
    }

    // Autocomplete dropdown -- only visible when there are results
    ListView {
        id: resultsList
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 200)
        visible: count > 0
        model: root.geocodeModel
        clip: true

        delegate: Rectangle {
            width: resultsList.width
            height: 40
            color: mouseArea.containsMouse ? Theme.surfaceAlt : "transparent"
            radius: Theme.radiusSmall

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingMedium
                text: model.display  // "City, State, Country" from GeocodeModel
                color: Theme.text
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    app.addGeocodedLocation(index);
                    searchField.text = "";
                }
            }
        }
    }
}
