import QtQuick
import "../core"

// Keyboard focus ring (DESIGN-SYSTEM §7, focus-visible): a 1 px ring drawn inside the owner while
// `shown` (the owner's activeFocus). Qt grants activeFocus by Tab or forced focus, not by a pointer
// press: none of these components sets activeFocusOnPress, so pointer users never see it. The owner
// sizes it with anchors.fill and passes its corner radius.
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
