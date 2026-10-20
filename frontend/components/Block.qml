import QtQuick
import "../core"

// Block (K42): the one shape chrome is made of. Flat chrome: a rounded fill (and an optional hairline). Keycap
// chrome (SekaiPop's "one block, everywhere"): an outline in Theme.line, a ring in Theme.ring between outline and
// fill, and a hard shadow straight down in the line colour; while `pressed` the face sinks onto its shadow and
// springs back with Theme.overshoot. Children land on the fill. Widths come from tokens, so no renderer here or in
// a caller branches on the theme's name (rule 4).
// The block's size includes the shadow: the face is `height - Theme.shadowDy` tall (`faceH`); centre content on
// `face` (anchors.centerIn: blk.face), not on the block.
Item {
    id: blk
    property color fill: Theme.containerHigh
    property real radius: Theme.rLg
    property bool pressed: false
    // A hairline in flat chrome (cards, popups); keycap always outlines.
    property color flatBorder: "transparent"
    property bool animate: visible
    // Thinner keycap ring for small things (chips, bar pills): 0..1 of the token ring.
    property real ringScale: 1
    readonly property real ringW: Theme.ringW * ringScale
    readonly property real inset: Theme.outlineW + ringW
    readonly property real faceH: height - Theme.shadowDy
    readonly property alias face: face
    default property alias content: fillRect.data

    implicitHeight: Theme.controlH + Theme.shadowDy

    Rectangle {
        visible: Theme.shadowDy > 0
        y: Theme.shadowDy
        width: blk.width
        height: blk.faceH
        radius: Math.min(blk.radius, height / 2)
        color: Theme.line
        antialiasing: true
    }
    Item {
        id: face
        width: blk.width
        height: blk.faceH
        y: blk.pressed ? Theme.shadowDy : 0
        Behavior on y {
            enabled: blk.animate && Theme.springOn
            NumberAnimation {
                duration: blk.pressed ? 70 : Theme.stdMs + 60
                easing.type: blk.pressed ? Easing.OutQuad : Easing.OutBack
                easing.overshoot: Theme.overshoot
            }
        }
        Rectangle {
            id: rim
            anchors.fill: parent
            radius: Math.min(blk.radius, height / 2)
            color: Theme.keycap ? Theme.ring : blk.fill
            border.width: Theme.keycap ? Theme.outlineW : (blk.flatBorder.a > 0 ? 1 : 0)
            border.color: Theme.keycap ? Theme.line : blk.flatBorder
            antialiasing: true
        }
        Rectangle {
            id: fillRect
            anchors.fill: parent
            anchors.margins: Theme.keycap ? blk.inset : 0
            radius: Math.max(0, Math.min(blk.radius, rim.height / 2) - (Theme.keycap ? blk.inset : 0))
            color: Theme.keycap ? blk.fill : "transparent"
            antialiasing: true
            Behavior on color { enabled: blk.animate; ColorAnimation { duration: Theme.quickMs } }
        }
    }
}
