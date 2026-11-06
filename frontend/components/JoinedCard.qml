import QtQuick
import QtQuick.Shapes
import Quickshell
import "../core"
import "sidebar"

// A card that stands on a bar or the frame's band (I428, docs/ux/layout.md "Draw modes", `layout.draw = dynamic`): the same
// one-sheet shape as the dock and the sidebars (ColumnShape), its material on its fill, fillets included. Fill the card's
// window area with it: the card's own box is the item less `pad` on each side (room for the fillets).
//   edge        the side it stands on: top, bottom (a horizontal bar) or left, right (a vertical one)
//   flushStart  the card's start (left, or top on a vertical bar) lies on the neighbour there: it merges instead of a fillet
//   flushEnd    the same at its end (right, or bottom)
// Static: a path changes only when a number does. Rule 4: no theme in here; tokens only.
Item {
    id: jc
    property string edge: "top"
    property bool flushStart: false
    property bool flushEnd: false
    property real pad: 0
    property real neck: Theme.rJoin
    property real radius: Theme.rLg
    property color fill: Theme.surfaceAlpha
    readonly property bool vertical: edge === "left" || edge === "right"
    // ColumnShape's outer side is its right: a flush start mirrors, and a left bar is its outer side.
    readonly property bool mirrorX: edge === "left" || (!vertical && flushStart && !flushEnd)
    readonly property bool mirrorY: edge === "bottom"
    readonly property var scaling: Scale {
        xScale: jc.mirrorX ? -1 : 1
        yScale: jc.mirrorY ? -1 : 1
        origin.x: jc.width / 2
        origin.y: jc.height / 2
    }
    // ColumnShape runs its open sides on past the neighbour's edge, under where its own window would end for the dock. Here the
    // window has room for the fillets, so they are cut: an overlap of the outline's width, enough to hide a rule under the card.
    readonly property real over: pad - Math.max(1, Theme.outlineW)
    readonly property bool cutL: edge === "left" || (!vertical && flushStart)
    readonly property bool cutR: edge === "right" || (!vertical && flushEnd)
    readonly property bool cutT: edge === "top" || (vertical && flushStart)
    readonly property bool cutB: edge === "bottom" || (vertical && flushEnd)
    Item {
        id: clipper
        x: jc.cutL ? jc.over : 0
        y: jc.cutT ? jc.over : 0
        width: jc.width - x - (jc.cutR ? jc.over : 0)
        height: jc.height - y - (jc.cutB ? jc.over : 0)
        clip: true
        Item {
            x: -clipper.x
            y: -clipper.y
            width: jc.width
            height: jc.height
            ColumnShape {
                id: shape
                anchors.fill: parent
                transform: jc.scaling
                x0: jc.pad
                x1: jc.width - jc.pad
                y0: jc.pad
                y1: jc.height - jc.pad
                openT: !jc.vertical || jc.flushStart
                openB: jc.vertical && jc.flushEnd
                openO: jc.vertical || jc.flushStart || jc.flushEnd
                neckT: jc.neck
                neckB: jc.neck
                neckO: jc.neck
                radius: jc.radius
                squareOuter: false
                flipX: jc.mirrorX
                flipY: jc.mirrorY
                ruled: Theme.frameOutline
                fill: jc.fill
            }
        }
    }
    // The material on the fill (the dock's and the sidebar's pattern, K59): a relief cut by a mask redrawn when the path changes.
    readonly property bool textured: visible && Theme.texShell && shape.shown
    Shape {
        id: maskShape
        visible: jc.textured
        anchors.fill: parent
        transform: jc.scaling
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: "white"
            PathSvg { path: jc.textured ? shape.fillPath : "" }
        }
    }
    StillCopy {
        id: maskCopy
        x: -100000
        width: jc.width
        height: jc.height
        sourceItem: jc.textured ? maskShape : null
        hideSource: true
    }
    Connections {
        target: jc.textured ? shape : null
        function onFillPathChanged() { maskCopy.scheduleUpdate() }
    }
    onTexturedChanged: if (textured) Qt.callLater(maskCopy.scheduleUpdate)
    Loader {
        anchors.fill: parent
        active: jc.textured
        sourceComponent: Relief { anchors.fill: parent; mask: maskCopy }
    }
}
