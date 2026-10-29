import QtQuick
import "../core"

// A rounded box that follows the look's corners (W56, I288): where a visible shape was a radiused Rectangle. Under
// round corners it is that Rectangle (no extra cost); under `theme.shape.corners = squircle` a SquircleRect draws it
// instead, on the profile's curve (`Theme.squircle`), made only then. A pill's end (a corner of half the shorter side
// or more) stays round, as Block's. Same `radius`, `color` and `border.width` / `border.color` as a Rectangle; a
// gradient, an invisible hit area or a clip stays a Rectangle.
Item {
    id: rb
    property real radius: 0
    property color color: "white"
    readonly property RoundPen border: RoundPen {}
    readonly property real bw: rb.border.color.a > 0 ? Math.max(0, rb.border.width) : 0
    readonly property bool sq: Theme.squircle > 0 && rb.radius > 0.5 && rb.radius < Math.min(rb.width, rb.height) / 2 - 0.5

    Rectangle {
        anchors.fill: parent
        visible: !rb.sq
        radius: rb.radius
        color: rb.color
        border.width: rb.bw
        border.color: rb.border.color
    }
    Loader {
        anchors.fill: parent
        active: rb.sq
        sourceComponent: SquircleRect {
            radius: rb.radius
            color: rb.color
            borderWidth: rb.bw
            borderColor: rb.border.color
        }
    }
}
