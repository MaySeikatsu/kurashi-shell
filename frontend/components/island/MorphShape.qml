import QtQuick
import QtQuick.Shapes
import "../../core"

// The island's one shape while it morphs (W21; Capsule's single morphing capsule, Vitreus's liquid neck): a rounded rect
// from (x0, y0), w x h, whose top lies inside the bar. Where its side crosses the bar's edge (`edgeY`) it is joined to the
// bar by concave fillets of up to `neck` px, in its own colours, so the card grows out of the bar rather than floating
// under it. Drawn in a top bar's frame; the Stage mirrors the whole item for a bottom bar (`flip`: the shadow still
// falls towards the screen's bottom then).
// Chrome comes from tokens only (rule 4): flat = fill with a `Theme.outline` hairline; keycap = Block's outline, ring
// (`ringScale` of the token ring) and hard shadow. The shadow is the body without its neck, so it shows under the card's
// free edge and never along the bar. A path is rebuilt only when a number changes: nothing runs while it stands (Ma).
Shape {
    id: sh
    property real x0: 0
    property real y0: 0
    property real w: 0
    property real h: 0
    property real rTop: 0
    property real rBot: 0
    property real edgeY: 0
    property real neck: 0
    property color fill: Theme.container
    property real ringScale: 1
    property bool flip: false

    readonly property real x1: x0 + w
    readonly property real y1: y0 + h
    // The neck forms once the bottom has room below the bar's edge for the fillet and the bottom corners.
    readonly property real rb: Math.max(0, Math.min(rBot, w / 2, h / 2))
    readonly property real rt: Math.max(0, Math.min(rTop, w / 2, h / 2, Math.max(0, edgeY - y0)))
    readonly property real n: Math.max(0, Math.min(neck, y1 - edgeY - rb, (y1 - edgeY) / 2))
    readonly property real ow: Theme.keycap ? Theme.outlineW : 1
    readonly property real gw: Theme.keycap ? Theme.ringW * ringScale : 0
    readonly property real sd: (flip ? -1 : 1) * Theme.shadowDy

    function f(v) { return Math.round(v * 100) / 100 }
    function arc(r, sweep, x, y) { return r > 0.05 ? " A " + f(r) + " " + f(r) + " 0 0 " + sweep + " " + f(x) + " " + f(y) : " L " + f(x) + " " + f(y) }
    // The outline of the shape inset by `d` (the sides and the free edges move in; the fillets keep their radius, so the
    // rings thin out towards the bar's edge and melt into it). `neckOn` false: the plain body (the shadow).
    function path(d, neckOn, dy) {
        var X0 = x0 + d, X1 = x1 - d, Y0 = y0 + d + dy, Y1 = y1 - d + dy
        if (X1 - X0 < 1 || Y1 - Y0 < 1) return ""
        var t = Math.max(0, rt - d), b = Math.max(0, rb - d)
        var nn = neckOn ? n : 0
        var E = edgeY + dy
        var s = "M " + f(X0 + t) + " " + f(Y0) + " L " + f(X1 - t) + " " + f(Y0) + arc(t, 1, X1, Y0 + t)
        if (nn > 0.5) s += " L " + f(X1) + " " + f(E) + " L " + f(X1 + nn) + " " + f(E) + arc(nn, 0, X1, E + nn)
        s += " L " + f(X1) + " " + f(Y1 - b) + arc(b, 1, X1 - b, Y1) + " L " + f(X0 + b) + " " + f(Y1) + arc(b, 1, X0, Y1 - b)
        if (nn > 0.5) s += " L " + f(X0) + " " + f(E + nn) + arc(nn, 0, X0 - nn, E) + " L " + f(X0) + " " + f(E)
        s += " L " + f(X0) + " " + f(Y0 + t) + arc(t, 1, X0 + t, Y0) + " Z"
        return s
    }

    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: Theme.shadowDy > 0 ? Theme.line : "transparent"
        PathSvg { path: sh.visible && Theme.shadowDy > 0 ? sh.path(0, false, sh.sd) : "" }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: Theme.keycap ? Theme.line : Theme.outline
        PathSvg { path: sh.visible ? sh.path(0, true, 0) : "" }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: Theme.keycap ? Theme.ring : sh.fill
        PathSvg { path: sh.visible ? sh.path(sh.ow, true, 0) : "" }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: Theme.keycap ? sh.fill : "transparent"
        PathSvg { path: sh.visible && Theme.keycap ? sh.path(sh.ow + sh.gw, true, 0) : "" }
    }
}
