import QtQuick
import QtQuick.Shapes
import "../core"

// Keyboard focus ring (DESIGN-SYSTEM §7, focus-visible): drawn on the owner while `shown` (the owner's activeFocus).
// Qt grants activeFocus by Tab or forced focus, not by a pointer press: none of these components sets
// activeFocusOnPress, so pointer users never see it. The owner sizes it with anchors.fill and passes its corner radius.
// W53.0a (K80): the look's focus style (`Theme.focusStyle`, data — rule 4) — "ring" (1 px, today's), "dotted" (a 1 px
// dotted line: 9x, XP, 7), "double" (2 px outer and a 1 px contrasting inner ring: fluent), "halo" (3 px outside at
// half the accent: the Macs) — at `Theme.focusOffset` (negative = inside) and `Theme.focusW`. The ring itself is this
// Rectangle's border; the other styles are made only while one is the look's and the ring is shown.
Rectangle {
    id: fr
    property bool shown: false
    property real corner: 0
    property color stroke: Theme.focusRing
    readonly property bool plain: Theme.focusStyle === "ring" && Theme.focusOffset === 0

    color: "transparent"
    border.width: plain ? Theme.focusW : 0
    border.color: stroke
    radius: corner
    visible: shown

    Loader {
        active: fr.shown && !fr.plain
        anchors.fill: parent
        anchors.margins: -(Theme.focusOffset + (Theme.focusStyle === "halo" ? 3 : 0))
        sourceComponent: Theme.focusStyle === "dotted" ? dottedC
            : Theme.focusStyle === "double" ? doubleC
            : Theme.focusStyle === "halo" ? haloC : ringC
    }

    Component {
        id: ringC
        Rectangle {
            color: "transparent"
            border.width: Theme.focusW
            border.color: fr.stroke
            radius: Math.max(0, fr.corner + Theme.focusOffset)
        }
    }
    Component {
        id: dottedC
        Shape {
            id: ds
            preferredRendererType: Shape.CurveRenderer
            readonly property real r: Math.max(0, Math.min(fr.corner + Theme.focusOffset, Math.min(width, height) / 2))
            readonly property real h: Theme.focusW / 2
            ShapePath {
                strokeColor: fr.stroke
                strokeWidth: Theme.focusW
                strokeStyle: ShapePath.DashLine
                dashPattern: [1, 1]
                fillColor: "transparent"
                startX: ds.r + ds.h; startY: ds.h
                PathLine { x: ds.width - ds.r - ds.h; y: ds.h }
                PathArc { x: ds.width - ds.h; y: ds.r + ds.h; radiusX: ds.r; radiusY: ds.r }
                PathLine { x: ds.width - ds.h; y: ds.height - ds.r - ds.h }
                PathArc { x: ds.width - ds.r - ds.h; y: ds.height - ds.h; radiusX: ds.r; radiusY: ds.r }
                PathLine { x: ds.r + ds.h; y: ds.height - ds.h }
                PathArc { x: ds.h; y: ds.height - ds.r - ds.h; radiusX: ds.r; radiusY: ds.r }
                PathLine { x: ds.h; y: ds.r + ds.h }
                PathArc { x: ds.r + ds.h; y: ds.h; radiusX: ds.r; radiusY: ds.r }
            }
        }
    }
    Component {
        id: doubleC
        Rectangle {
            color: "transparent"
            border.width: 2 * Theme.focusW
            border.color: fr.stroke
            radius: Math.max(0, fr.corner + Theme.focusOffset)
            // The inner ring contrasts with the outer one: the ground's colour.
            Rectangle {
                anchors.fill: parent
                anchors.margins: parent.border.width
                color: "transparent"
                border.width: Theme.focusW
                border.color: Theme.surface
                radius: Math.max(0, parent.radius - parent.border.width)
            }
        }
    }
    Component {
        id: haloC
        Rectangle {
            color: "transparent"
            border.width: 3
            border.color: Qt.alpha(fr.stroke, 0.5)
            radius: Math.max(0, fr.corner + Theme.focusOffset + 3)
        }
    }
}
