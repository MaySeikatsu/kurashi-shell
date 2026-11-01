import QtQuick
import QtQuick.Shapes
import "../core"

// Keyboard focus ring (DESIGN-SYSTEM §7, focus-visible): drawn on the owner while `shown` (the owner's activeFocus).
// Qt grants activeFocus by Tab or forced focus, not by a pointer press: none of these components sets
// activeFocusOnPress, so pointer users never see it. The owner sizes it with anchors.fill and passes its corner radius.
// W53.0a (K80): the look's focus style (`Theme.focusStyle`, data — rule 4) — "ring" (1 px, today's), "dotted" (a 1 px
// dotted line: 9x, XP, 7), "double" (2 px outer and a 1 px contrasting inner ring: fluent), "halo" (3 px outside at
// half the accent: the Macs), "brush" (W53.7, washi: a faint ring and under it one ink stroke, thick in its middle and
// thinning to both ends, as a brush lifts) — at `Theme.focusOffset` (negative = inside) and `Theme.focusW`. The ring
// itself is this Rectangle's border; the other styles are made only while one is the look's and the ring is shown.
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
            : Theme.focusStyle === "halo" ? haloC
            : Theme.focusStyle === "brush" ? brushC : ringC
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
            // The geometry renderer, unsmoothed: it draws dashes (the curve renderer strokes them solid) on whole px.
            antialiasing: false
            readonly property real r: Math.max(0, Math.min(fr.corner + Theme.focusOffset, Math.min(width, height) / 2))
            readonly property real h: Theme.focusW / 2
            ShapePath {
                strokeColor: fr.stroke
                strokeWidth: Theme.focusW
                strokeStyle: ShapePath.DashLine
                // Flat caps: a square cap would grow each 1 px dot over its gap (a solid line).
                capStyle: ShapePath.FlatCap
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
            // The inner ring contrasts with the outer one: white over a dark outer ring, black over a light one, at 70 %
            // (WinUI's FocusStrokeColorInner, #b3ffffff / #b3000000) — so a ring inked for a dark ground keeps its pair.
            Rectangle {
                anchors.fill: parent
                anchors.margins: parent.border.width
                color: "transparent"
                border.width: Theme.focusW
                border.color: fr.stroke.hslLightness < 0.5 ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(0, 0, 0, 0.7)
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
    Component {
        id: brushC
        Item {
            id: bc
            // The stroke's thickest point (px): 2.5 focus widths, 3 px at least — ink, not a hairline.
            readonly property real t: Math.max(3, 2.5 * Theme.focusW)
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: Theme.crisp(1, Screen.devicePixelRatio)
                border.color: Qt.alpha(fr.stroke, 0.28)
                radius: Math.max(0, fr.corner + Theme.focusOffset)
            }
            // One closed path under the control: the upper edge bows up a little, the lower edge down more, meeting in
            // fine points; it starts a little in from the left and stops short of the right (a hand, not a ruler). Static.
            Shape {
                anchors { left: parent.left; right: parent.right; top: parent.bottom; topMargin: 2 }
                height: bc.t + 2
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: fr.stroke
                    startX: bc.width * 0.04; startY: bc.t * 0.55
                    PathCubic {
                        x: bc.width * 0.93; y: bc.t * 0.35
                        control1X: bc.width * 0.3; control1Y: -bc.t * 0.15
                        control2X: bc.width * 0.7; control2Y: 0
                    }
                    PathCubic {
                        x: bc.width * 0.04; y: bc.t * 0.55
                        control1X: bc.width * 0.72; control1Y: bc.t * 1.25
                        control2X: bc.width * 0.28; control2Y: bc.t * 1.35
                    }
                }
            }
        }
    }
}
