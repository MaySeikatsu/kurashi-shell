import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."
import "../pen.js" as Pen

// The sidebar's one shape while it grows out of the bar and stands (W34, docs/ux/motion.md "the bar reaches out"). Drawn
// in a canonical frame: a RIGHT sidebar whose bar edge is the frame's top (`joinTop`, y = 0) or its right side
// (`joinSide`, x = width: a side bar on the sidebar's own side), or no bar at all; Sidebar.qml mirrors the frame for the
// left side and for a bar at the bottom. The body is the rect (x0, y0) – (x1, y1). Where it meets the bar's edge it is
// joined to it by concave fillets of up to `neck` px (the island's neck, MorphShape's strip topology, turned to the bar's
// end): the edge joined to the bar lies `K` px past the window, so no outline runs along it and the bar and the column
// read as one sheet. A fillet takes only the room there is (a flush panel at rest has none on its outer side).
// Where the bar rules its edge (`ruled`: line chrome) the outline runs round the fillet concentrically and meets the
// bar's rule tangentially; elsewhere the fillet's outline thins out towards the bar's edge and melts into it.
// Every layer is one closed path; outline and ring are bands (odd-even), so the fill may be translucent. Chrome from
// tokens only (rule 4): outline `Theme.outlineW` in `Theme.outlineColor` (flat: a 1 px `Theme.outline` hairline); with
// `chrome` (the floating style) also the ring and the hard shadow. Paths are rebuilt only when a number changes (Ma).
Shape {
    id: sh
    property real x0: 0
    property real y0: 0
    property real x1: 0
    property real y1: 0
    property bool joinTop: false
    property bool joinSide: false
    // Convex corners (canonical: TL, BL are the inner ones) and the fillet size.
    property real radius: Theme.rLg
    property real neck: Theme.rLg
    // Corners on the outer side are square once they lie on the frame's outer edge (the panel: flush with the screen).
    property bool squareOuter: true
    property bool ruled: false
    property bool chrome: false        // ring and hard shadow (the floating style's block)
    property bool flipY: false         // the frame is mirrored vertically: the hard shadow still falls down on screen
    property bool flipX: false         // the frame is mirrored horizontally (a left sidebar): it still falls the screen's way
    property color fill: Theme.panel

    readonly property real ow: Theme.outlineW > 0 ? Theme.outlineW : 1
    readonly property color oc: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
    readonly property real gw: chrome ? Theme.ringW * 0.5 : 0
    // The hard shadow's vector (K67; `Theme.shadowDy` straight down by default), in the canonical frame.
    readonly property real sdx: chrome ? (flipX ? -1 : 1) * Theme.sinkX : 0
    readonly property real sdy: chrome ? Theme.sinkY : 0
    readonly property real sd: (flipY ? -1 : 1) * sdy
    readonly property bool casts: sdx !== 0 || sdy !== 0
    // How far a joined edge lies past the window: further than every inset and the shadow (either way it falls).
    readonly property real k: ow + gw + Math.max(Math.abs(sdx), Math.abs(sdy), chrome ? Theme.shadowDy : 0) + 4
    readonly property real bw: x1 - x0
    readonly property real bh: y1 - y0
    readonly property bool shown: visible && bw >= 1 && bh >= 1

    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
    readonly property real rc: Math.max(0, Math.min(radius, bw / 2, bh / 2))
    // An outer corner squares off as it reaches the outer edge (a panel landing flush), smoothly.
    readonly property real ro: squareOuter ? Math.max(0, Math.min(rc, 2 * (width - x1))) : rc
    // The fillets: under a top bar on the inner (left) and outer (right) side; beside a side bar at the top and bottom.
    readonly property real fL: joinTop ? Math.max(0, Math.min(neck, y1 - rc, y1 / 2, x0)) : 0
    readonly property real fR: joinTop ? Math.max(0, Math.min(neck, y1 - ro, y1 / 2, width - x1)) : 0
    readonly property real fT: joinSide ? Math.max(0, Math.min(neck, y0, bw - rc, bw / 2)) : 0
    readonly property real fB: joinSide ? Math.max(0, Math.min(neck, height - y1, bw - rc, bw / 2)) : 0

    function f(v) { return Math.round(v * 100) / 100 }
    function arc(r, sweep, x, y) { return r > 0.05 ? " A " + f(r) + " " + f(r) + " 0 0 " + sweep + " " + f(x) + " " + f(y) : " L " + f(x) + " " + f(y) }
    function ln(x, y) { return " L " + f(x) + " " + f(y) }

    // The outline inset by `d`, moved down by `dy` (the hard shadow); `fl` false leaves the fillets out (the shadow).
    function path(d, fl, dy) {
        if (!shown) return ""
        if (joinTop) return topPath(d, fl, dy)
        if (joinSide) return sidePath(d, fl, dy)
        return freePath(d, dy)
    }
    // Under a top bar: the top edge lies in the bar (y = −k), the sides join the bar's edge (y = 0) through fillets.
    function topPath(d, fl, dy) {
        var X0 = x0 + d, X1 = x1 - d, Y1 = y1 - d + dy, T = -k + d + dy, E = dy
        if (X1 - X0 < 1 || Y1 - E < 1) return ""
        var bl = Math.max(0, rc - d), br = Math.max(0, ro - d)
        var a = fl ? fL : 0, b = fl ? fR : 0
        var s = "M " + f(X0) + " " + f(T) + ln(X1, T)
        if (b > 0.5) {
            if (ruled) s += ln(X1, E - d) + ln(x1 + b, E - d) + arc(b + d, 0, X1, E + b)
            else s += ln(X1, E) + ln(X1 + b, E) + arc(b, 0, X1, E + b)
        }
        s += ln(X1, Y1 - br) + arc(br, 1, X1 - br, Y1) + ln(X0 + bl, Y1) + arc(bl, 1, X0, Y1 - bl)
        if (a > 0.5) {
            if (ruled) s += ln(X0, E + a) + arc(a + d, 0, x0 - a, E - d) + ln(X0, E - d)
            else s += ln(X0, E + a) + arc(a, 0, X0 - a, E) + ln(X0, E)
        }
        return s + ln(X0, T) + " Z"
    }
    // Beside a side bar on the sidebar's side: the outer side lies in the bar (x = width + k), the top and bottom edges
    // join the bar's edge (x = width) through fillets.
    function sidePath(d, fl, dy) {
        var S = width, R = width + k - d
        var X0 = x0 + d, Y0 = y0 + d + dy, Y1 = y1 - d + dy
        if (R - X0 < 1 || Y1 - Y0 < 1) return ""
        var tl = Math.max(0, rc - d), bl = Math.max(0, rc - d)
        var a = fl ? fT : 0, b = fl ? fB : 0
        var s = "M " + f(X0) + " " + f(Y0 + tl) + arc(tl, 1, X0 + tl, Y0)
        if (a > 0.5) {
            if (ruled) s += ln(S - a, Y0) + arc(a + d, 0, S + d, y0 - a + dy) + ln(R, y0 - a + dy)
            else s += ln(S - a, Y0) + arc(a, 0, S, Y0 - a) + ln(R, Y0 - a)
        } else s += ln(R, Y0)
        if (b > 0.5) {
            if (ruled) s += ln(R, y1 + b + dy) + ln(S + d, y1 + b + dy) + arc(b + d, 0, S - b, Y1)
            else s += ln(R, Y1 + b) + ln(S, Y1 + b) + arc(b, 0, S - b, Y1)
        } else s += ln(R, Y1)
        return s + ln(X0 + bl, Y1) + arc(bl, 1, X0, Y1 - bl) + ln(X0, Y0 + tl) + " Z"
    }
    // No bar to join: a rounded rect (the outer corners square on the frame's edge, for the panel).
    function freePath(d, dy) {
        var X0 = x0 + d, X1 = x1 - d, Y0 = y0 + d + dy, Y1 = y1 - d + dy
        if (X1 - X0 < 1 || Y1 - Y0 < 1) return ""
        var ri = Math.max(0, rc - d), rr = Math.max(0, ro - d)
        return "M " + f(X0 + ri) + " " + f(Y0) + ln(X1 - rr, Y0) + arc(rr, 1, X1, Y0 + rr) + ln(X1, Y1 - rr) + arc(rr, 1, X1 - rr, Y1)
            + ln(X0 + ri, Y1) + arc(ri, 1, X0, Y1 - ri) + ln(X0, Y0 + ri) + arc(ri, 1, X0 + ri, Y0) + " Z"
    }
    function band(a, b) { var p = path(a, true, 0), q = path(b, true, 0); return p === "" ? "" : p + " " + q }

    // The fill's own path (inside the outline and the ring): Sidebar.qml clips the column's relief to it.
    readonly property string fillPath: shown ? path(ow + gw, true, 0) : ""
    // The body's rect without the fillets (the soft shadow's).
    readonly property rect bodyRect: Qt.rect(x0, joinTop ? 0 : y0, joinSide ? width - x0 : bw, joinTop ? y1 : bh)

    // K62: with a pen in effect the pen draws the outline along its centre line (one closed line; the part in the bar
    // lies past the window).
    readonly property bool penOn: Theme.penOutline
    function penPaths() {
        if (!shown || !penOn) return []
        var subs = Pen.svgPaths(path(ow / 2, true, 0)), out = []
        for (var i = 0; i < subs.length; i++) out.push({ points: subs[i].pts, closed: subs[i].closed, width: ow })
        return out
    }
    Loader {
        anchors.fill: parent
        active: sh.penOn && sh.shown
        sourceComponent: PenOutline {
            color: sh.oc
            lineWidth: sh.ow
            seed: 0x51DE3
            paths: sh.penPaths()
        }
    }

    preferredRendererType: Shape.CurveRenderer
    // The hard shadow: the outline moved along the vector — down the path, across by this layer's place (z −1: under the
    // shape's own layers).
    Shape {
        z: -1
        x: sh.sdx
        width: sh.width
        height: sh.height
        visible: sh.casts
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: sh.casts ? Theme.line : "transparent"
            PathSvg { path: sh.casts ? sh.path(0, false, sh.sd) : "" }
        }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillColor: sh.penOn ? "transparent" : sh.oc
        PathSvg { path: sh.penOn ? "" : sh.band(0, sh.ow) }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillColor: sh.gw > 0 ? Theme.ring : "transparent"
        PathSvg { path: sh.gw > 0 ? sh.band(sh.ow, sh.ow + sh.gw) : "" }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: sh.fill
        PathSvg { path: sh.fillPath }
    }
}
