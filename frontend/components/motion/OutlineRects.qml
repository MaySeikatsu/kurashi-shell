import QtQuick
import QtQuick.Shapes
import "../../core"

// The outline form's rectangles (Outline.qml `rects`), drawn in the look's outline role (its outline colour and width, at
// least 2 px so a step reads; pixel looks on whole pixels). Put it in the same frame as the form's geometry (a bottom
// bar's surface mirrors it with its shape). Drawn only while there are rects (Ma).
Shape {
    id: o
    property var rects: []
    readonly property real lw: Math.max(2, Math.round(Theme.outlineW > 0 ? Theme.outlineW : 2))
    readonly property color ink: Theme.outlineW > 0 ? Theme.outlineColor : Theme.fg
    visible: rects.length > 0
    preferredRendererType: Shape.CurveRenderer
    function f(v) { return Math.round(v * 100) / 100 }
    function px(v) { return Theme.pixelType ? Math.round(v) : v }
    // A rounded rect's centre line, inset by half the line so the outline lies inside the rect (as a card's border).
    function path(r) {
        if (!r) return ""
        var d = lw / 2, x0 = px(r.x) + d, y0 = px(r.y) + d, x1 = px(r.x + r.w) - d, y1 = px(r.y + r.h) - d
        if (x1 - x0 < 1 || y1 - y0 < 1) return ""
        var rr = Math.max(0, Math.min(r.r - d, (x1 - x0) / 2, (y1 - y0) / 2))
        function arc(x, y) { return rr > 0.05 ? " A " + f(rr) + " " + f(rr) + " 0 0 1 " + f(x) + " " + f(y) : " L " + f(x) + " " + f(y) }
        return "M " + f(x0 + rr) + " " + f(y0) + " L " + f(x1 - rr) + " " + f(y0) + arc(x1, y0 + rr)
            + " L " + f(x1) + " " + f(y1 - rr) + arc(x1 - rr, y1) + " L " + f(x0 + rr) + " " + f(y1) + arc(x0, y1 - rr)
            + " L " + f(x0) + " " + f(y0 + rr) + arc(x0 + rr, y0) + " Z"
    }
    ShapePath {
        strokeWidth: o.lw
        strokeColor: o.rects.length > 1 ? Qt.alpha(o.ink, o.ink.a * o.rects[0].a) : "transparent"
        fillColor: "transparent"
        joinStyle: ShapePath.MiterJoin
        PathSvg { path: o.rects.length > 1 ? o.path(o.rects[0]) : "" }
    }
    ShapePath {
        strokeWidth: o.lw
        strokeColor: o.rects.length > 0 ? Qt.alpha(o.ink, o.ink.a * o.rects[o.rects.length - 1].a) : "transparent"
        fillColor: "transparent"
        joinStyle: ShapePath.MiterJoin
        PathSvg { path: o.rects.length > 0 ? o.path(o.rects[o.rects.length - 1]) : "" }
    }
}
