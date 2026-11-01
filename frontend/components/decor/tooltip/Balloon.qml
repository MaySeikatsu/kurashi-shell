import QtQuick
import QtQuick.Shapes
import "../../../core"

// Balloon (W53.2): a balloon tip — Windows XP's and 7's notification idiom (docs/ux/styles.md §2, §3; measured on
// guidebookgallery.org's pics/gui/desktop/firstrun/winxppro-2-1.png, x 416–740, y 487–563: #ffffe1 in 1 px of black,
// corners ~7 px, the tail a straight-sided wedge from the body's edge to the anchor; 7's on Microsoft's UX guide
// capture learn.microsoft.com/…/uxguide/images/ctrl-balloons-image2.png: white to a pale blue-grey, a grey rim, corners
// ~3 px, a soft shadow). One outline — body and tail together — filled `[decor] tooltip.fill` (a light top when the
// look's radius is small: 7's gradient), stroked `tooltip.border`, `tooltip.radius` round; with `tooltip.tail` the tail
// sticks out of the part's box on `tailSide` at `tailAt` (the caller leaves it the room: `tail` px). Static.
TooltipBase {
    id: bl
    readonly property string fillRole: Theme.decor("tooltip.fill", "")
    readonly property color fill: fillRole !== "" ? fillRole : Theme.color("color.info", "#ffffe1")
    readonly property string borderRole: Theme.decor("tooltip.border", "")
    readonly property color rim: borderRole !== "" ? borderRole : Theme.fg
    readonly property real r: Theme.decor("tooltip.radius", -1) >= 0 ? Theme.decor("tooltip.radius", -1) : 7
    readonly property bool hasTail: Theme.decor("tooltip.tail", false) === true
    // The tail's length out of the box and its width at the body.
    readonly property real tail: hasTail ? 18 : 0
    readonly property real tw: 14
    readonly property real at: Math.max(r + 2, Math.min((tailSide === "left" || tailSide === "right" ? height : width) - r - tw - 2, tailAt))
    readonly property real o: 0.5

    // 7's soft shadow (XP drew none: corners ≥ 6 px say XP).
    Rectangle {
        visible: bl.r < 6
        x: 2; y: 3
        width: bl.width; height: bl.height
        radius: bl.r
        color: Qt.rgba(0, 0, 0, 0.18)
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: bl.rim
            strokeWidth: 1
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: bl.height
                GradientStop { position: 0; color: bl.r < 6 ? Qt.lighter(bl.fill, 1.04) : bl.fill }
                GradientStop { position: 1; color: bl.r < 6 ? Qt.tint(bl.fill, Qt.rgba(0.55, 0.6, 0.75, 0.16)) : bl.fill }
            }
            startX: bl.r + bl.o; startY: bl.o
            // Top edge (a tail on top cuts in at `at`).
            PathLine { x: bl.tailSide === "top" && bl.hasTail ? bl.at : bl.r + bl.o; y: bl.o }
            PathLine { x: bl.tailSide === "top" && bl.hasTail ? bl.at + bl.tw * 0.15 : bl.r + bl.o; y: bl.tailSide === "top" && bl.hasTail ? -bl.tail : bl.o }
            PathLine { x: bl.tailSide === "top" && bl.hasTail ? bl.at + bl.tw : bl.r + bl.o; y: bl.o }
            PathLine { x: bl.width - bl.r - bl.o; y: bl.o }
            PathArc { x: bl.width - bl.o; y: bl.r + bl.o; radiusX: bl.r; radiusY: bl.r }
            // Right edge.
            PathLine { x: bl.width - bl.o; y: bl.tailSide === "right" && bl.hasTail ? bl.at : bl.r + bl.o }
            PathLine { x: bl.tailSide === "right" && bl.hasTail ? bl.width + bl.tail : bl.width - bl.o; y: bl.tailSide === "right" && bl.hasTail ? bl.at + bl.tw * 0.15 : bl.r + bl.o }
            PathLine { x: bl.width - bl.o; y: bl.tailSide === "right" && bl.hasTail ? bl.at + bl.tw : bl.r + bl.o }
            PathLine { x: bl.width - bl.o; y: bl.height - bl.r - bl.o }
            PathArc { x: bl.width - bl.r - bl.o; y: bl.height - bl.o; radiusX: bl.r; radiusY: bl.r }
            // Bottom edge, right to left (XP's tail leans toward the anchor's side).
            PathLine { x: bl.tailSide === "bottom" && bl.hasTail ? bl.at + bl.tw : bl.width - bl.r - bl.o; y: bl.height - bl.o }
            PathLine { x: bl.tailSide === "bottom" && bl.hasTail ? bl.at + bl.tw * 0.85 : bl.width - bl.r - bl.o; y: bl.tailSide === "bottom" && bl.hasTail ? bl.height + bl.tail : bl.height - bl.o }
            PathLine { x: bl.tailSide === "bottom" && bl.hasTail ? bl.at : bl.width - bl.r - bl.o; y: bl.height - bl.o }
            PathLine { x: bl.r + bl.o; y: bl.height - bl.o }
            PathArc { x: bl.o; y: bl.height - bl.r - bl.o; radiusX: bl.r; radiusY: bl.r }
            // Left edge, bottom to top.
            PathLine { x: bl.o; y: bl.tailSide === "left" && bl.hasTail ? bl.at + bl.tw : bl.height - bl.r - bl.o }
            PathLine { x: bl.tailSide === "left" && bl.hasTail ? -bl.tail : bl.o; y: bl.tailSide === "left" && bl.hasTail ? bl.at + bl.tw * 0.85 : bl.height - bl.r - bl.o }
            PathLine { x: bl.o; y: bl.tailSide === "left" && bl.hasTail ? bl.at : bl.height - bl.r - bl.o }
            PathLine { x: bl.o; y: bl.r + bl.o }
            PathArc { x: bl.r + bl.o; y: bl.o; radiusX: bl.r; radiusY: bl.r }
        }
    }
}
