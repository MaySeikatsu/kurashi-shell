import QtQuick
import QtQuick.Shapes
import "../core"
import "../core/corner.js" as Corner

// A rectangle with squircle corners (`theme.shape.corners = squircle`, I281) where a Rectangle drew a rounded one: its
// fill and its border inside its edge (as a Rectangle's), stroked along the border's centre line. A corner of half the
// shorter side or more is a pill's end and stays round. Only made while the look is a squircle one (Block's Loaders).
Shape {
    id: sr
    property real radius: 0
    property color color: "transparent"
    property real borderWidth: 0
    property color borderColor: "transparent"
    // I489 (session 29): the corner's shape beside its curve (`theme.join_corner`: chamfer, steps, bulge, square) for a
    // box that is a sheet of its own (a floating card, a sidebar's section, the notification centre); "" leaves the
    // corner round or squircle, as before.
    property string join: ""
    // The radius the box's own contour has, when this item is that box inset (a mask a line's width in): the shaped
    // corners of the inset are then the contour's own, moved in (corner.js `ref`). -1: this item's `radius`.
    property real refRadius: -1
    preferredRendererType: Shape.CurveRenderer

    readonly property real half: Math.min(width, height) / 2
    function f(v) { return Math.round(v * 100) / 100 }
    // The box with round corners whose arcs carry the contour's radius, for corner.js to shape.
    function arcs(x, y, w, h, r) {
        var m = Math.max(0, Math.min(w, h) / 2), ref = f(refRadius >= 0 ? refRadius : radius)
        r = Math.min(Math.max(0, r), m)
        if (r <= 0.05) return "M " + f(x) + " " + f(y) + " L " + f(x + w) + " " + f(y) + " L " + f(x + w) + " " + f(y + h) + " L " + f(x) + " " + f(y + h) + " Z"
        var a = " A " + f(r) + " " + f(r) + " " + ref + " 0 1 ", x1 = x + w, y1 = y + h
        return "M " + f(x + r) + " " + f(y) + " L " + f(x1 - r) + " " + f(y) + a + f(x1) + " " + f(y + r)
            + " L " + f(x1) + " " + f(y1 - r) + a + f(x1 - r) + " " + f(y1)
            + " L " + f(x + r) + " " + f(y1) + a + f(x) + " " + f(y1 - r)
            + " L " + f(x) + " " + f(y + r) + a + f(x + r) + " " + f(y) + " Z"
    }
    function box(x, y, w, h, r, m) {
        var sq = r < half - m - 0.5 ? Theme.squircle : 0
        return join !== "" ? Corner.squircled(arcs(x, y, w, h, r), sq, join) : Corner.rect(x, y, w, h, r, r, r, r, sq)
    }
    readonly property string outer: width < 1 || height < 1 ? "" : box(0, 0, width, height, radius, 0)
    readonly property real bw: Math.max(0, borderWidth)
    readonly property real ir: Math.max(0, radius - bw)
    readonly property string inner: bw <= 0 || width <= 2 * bw || height <= 2 * bw ? ""
        : box(bw, bw, width - 2 * bw, height - 2 * bw, ir, bw)

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: sr.color
        PathSvg { path: sr.color.a > 0 ? (sr.inner !== "" ? sr.inner : sr.outer) : "" }
    }
    // The border as a stroke along its centre line (an odd-even band between two squircles is uneven: their curves are
    // not parallel, and the band thinned to a speck where a corner meets its side, W56).
    readonly property real mr: Math.max(0, radius - bw / 2)
    readonly property string mid: bw <= 0 || width <= bw || height <= bw ? ""
        : box(bw / 2, bw / 2, width - bw, height - bw, mr, bw / 2)
    ShapePath {
        strokeWidth: sr.bw > 0 ? sr.bw : -1
        strokeColor: sr.borderColor
        fillColor: "transparent"
        PathSvg { path: sr.mid !== "" && sr.borderColor.a > 0 ? sr.mid : "" }
    }
}
