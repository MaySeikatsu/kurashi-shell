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
    // I471d (K121): a torn edge. By file (see below): a host without EdgeWarp keeps its clean edge.
    readonly property Component tornEffect: Theme.edgeTorn === true ? Qt.createComponent("EdgeWarp.qml") : null
    layer.enabled: tornEffect !== null && tornEffect.status === Component.Ready && rb.color.a > 0.5 && rb.width > 14 && rb.height > 14
    layer.effect: tornEffect

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
    // By file, not by type: RoundBox is linked into other hosts (the web dock's) that have neither Wash nor PenOutline; a
    // type named here would have to resolve there too. They load only in Settings.
    Loader {
        anchors.fill: parent
        anchors.margins: rb.lineW
        active: rb.washed
        source: active ? "Wash.qml" : ""
        onLoaded: {
            item.radius = Qt.binding(function () { return Math.max(0, rb.radius - rb.lineW) })
            item.fill = Qt.binding(function () { return rb.color })
        }
    }
    Loader {
        anchors.fill: parent
        active: rb.penned
        source: active ? "PenOutline.qml" : ""
        onLoaded: {
            item.radius = Qt.binding(function () { return rb.radius })
            item.color = Qt.binding(function () { return rb.border.color })
            item.lineWidth = Qt.binding(function () { return rb.bw })
            item.anchor = rb
        }
    }
}
