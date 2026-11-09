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

    // Session 26: in Settings (Theme.hosted) a box takes the shell's pen for its outline (K62) and the chrome's wash on a
    // ground's fill (I460), as the shell's own blocks do; the shell's boxes keep their straight line and flat fill.
    readonly property bool penned: Theme.hosted && Theme.penOutline && rb.bw > 0
    readonly property bool washed: Theme.hosted && Theme.washOn && rb.color.a > 0.99
        && (Qt.colorEqual(rb.color, Theme.surface) || Qt.colorEqual(rb.color, Theme.container)
            || Qt.colorEqual(rb.color, Theme.tok("color.surface_container_low", "#000")))
    readonly property real lineW: rb.penned ? 0 : rb.bw

    Rectangle {
        anchors.fill: parent
        visible: !rb.sq
        radius: rb.radius
        color: rb.color
        border.width: rb.lineW
        border.color: rb.border.color
    }
    Loader {
        anchors.fill: parent
        active: rb.sq
        sourceComponent: SquircleRect {
            radius: rb.radius
            color: rb.color
            borderWidth: rb.lineW
            borderColor: rb.border.color
        }
    }
    Loader {
        anchors.fill: parent
        anchors.margins: rb.lineW
        active: rb.washed
        sourceComponent: Wash { radius: Math.max(0, rb.radius - rb.lineW); fill: rb.color }
    }
    Loader {
        anchors.fill: parent
        active: rb.penned
        sourceComponent: PenOutline { radius: rb.radius; color: rb.border.color; lineWidth: rb.bw; anchor: rb }
    }
}
