import QtQuick
import "../core"

// Keyboard focus ring (DESIGN-SYSTEM §7, focus-visible): a 1 px ring drawn inside the owner while
// `shown` (the owner's activeFocus). Owners take focus by Tab only (activeFocusOnTab, never
// activeFocusOnPress, no forceActiveFocus on click), so a pointer press does not show the ring.
Rectangle {
    property bool shown: false
    property real corner: 0
    property color stroke: Theme.focusRing

    color: "transparent"
    border.width: 1
    border.color: stroke
    radius: corner
    visible: shown
}
