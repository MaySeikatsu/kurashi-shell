import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."
import "../pen.js" as Pen
import "../../core/corner.js" as Corner

// A column that stands on what is under it (K71, docs/ux/layout.md "Draw modes"): the sidebar, and the dock in its joined
// modes. Drawn in a canonical frame — a column whose OUTER side is the frame's right side (x = width) and whose ends are
// its top (start) and bottom (end); the caller mirrors the item for a left column, and the dock turns it to its edge.
// The body is the rect (x0, y0) – (x1, y1). A side that meets a neighbour (`openT` the start, `openB` the end, `openO`
// the outer side: a docked bar, the frame's band or the screen edge) lies `k` px past it, so no outline runs along it
// and column and neighbour read as one sheet; where a closed side meets an open one's edge the two are joined by a
// concave fillet of up to `neckT` / `neckB` / `neckO` px (the island's neck, MorphShape's strip topology, turned to the
// neighbour; 0 = a straight join, the connected mode). A fillet takes only the room there is (a column flush with its
// side has none on its outer side). The remaining corners are convex, `radius`; an outer one squares off on the frame's
// outer edge (`squareOuter`, a column landing flush).
// Where the neighbour rules its edge (`ruled`: line chrome) the outline runs round the fillet concentrically and meets the
// rule tangentially; elsewhere the fillet's outline thins out towards the neighbour's edge and melts into it.
// Every layer is one closed path; outline and ring are bands (odd-even), so the fill may be translucent. Chrome from
// tokens only (rule 4): outline `Theme.outlineW` in `Theme.outlineColor` (flat: a 1 px `Theme.outline` hairline); with
// `chrome` (the floating mode) also the ring and the hard shadow. Paths are rebuilt only when a number changes (Ma).
Shape {
    id: sh
    property real x0: 0
    property real y0: 0
    property real x1: 0
    property real y1: 0
    property bool openT: false
    property bool openB: false
    property bool openO: false
    property real neckT: 0
    property real neckB: 0
    property real neckO: 0
    property real radius: Theme.rLg
    // Outer corners are square once they lie on the frame's outer edge (flush with the screen).
    property bool squareOuter: true
    property bool ruled: false
    property bool chrome: false        // ring and hard shadow (the floating mode's block)
    property bool flipY: false         // the frame is mirrored vertically: the hard shadow still falls down on screen
    property bool flipX: false         // the frame is mirrored horizontally (a left column): it still falls the screen's way
    property color fill: Theme.panel

    // A shape joined to the frame's ruled band (`ruled`) is outlined as the frame is (its ink and stroke, I303).
    readonly property real ow: ruled ? Theme.frameOutlineW : (Theme.outlineW > 0 ? Theme.outlineW : 1)
    readonly property color oc: ruled ? Theme.frameOutlineColor : (Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline)
    readonly property real gw: chrome ? Theme.ringW * 0.5 : 0
    // The hard shadow's vector (K67; `Theme.shadowDy` straight down by default), in the canonical frame.
    readonly property real sdx: chrome ? (flipX ? -1 : 1) * Theme.sinkX : 0
    readonly property real sdy: chrome ? Theme.sinkY : 0
    readonly property real sd: (flipY ? -1 : 1) * sdy
    readonly property bool casts: sdx !== 0 || sdy !== 0
    // How far an open side lies past its neighbour's edge: further than every inset and the shadow (either way it falls).
    readonly property real k: ow + gw + Math.max(Math.abs(sdx), Math.abs(sdy), chrome ? Theme.shadowDy : 0) + 4
    readonly property real bw: x1 - x0
    readonly property real bh: y1 - y0
    readonly property bool shown: visible && bw >= 1 && bh >= 1

    readonly property real rc: Math.max(0, Math.min(radius, bw / 2, bh / 2))
    // An outer corner squares off as it reaches the outer edge (a column landing flush), smoothly.
    readonly property real ro: squareOuter ? Math.max(0, Math.min(rc, 2 * (width - x1))) : rc
    readonly property real rTL: openT ? 0 : rc
    readonly property real rBL: openB ? 0 : rc
    readonly property real rTR: openT || openO ? 0 : ro
    readonly property real rBR: openB || openO ? 0 : ro
    // The fillets: at the start on the inner (fTi) and outer (fTo) side, at the end likewise, along the outer side at its
    // two ends (fOt, fOb).
    function room(v) { return Math.max(0, v) }
    readonly property real fTi: openT ? room(Math.min(neckT, bh - rBL, bh / 2, x0)) : 0
    readonly property real fTo: openT && !openO ? room(Math.min(neckT, bh - rBR, bh / 2, width - x1)) : 0
    readonly property real fBi: openB ? room(Math.min(neckB, bh - rTL, bh / 2, x0)) : 0
    readonly property real fBo: openB && !openO ? room(Math.min(neckB, bh - rTR, bh / 2, width - x1)) : 0
    readonly property real fOt: openO && !openT ? room(Math.min(neckO, y0, bw - rc, bw / 2)) : 0
    readonly property real fOb: openO && !openB ? room(Math.min(neckO, height - y1, bw - rc, bw / 2)) : 0

    function f(v) { return Math.round(v * 100) / 100 }
    function arc(r, sweep, x, y) { return r > 0.05 ? " A " + f(r) + " " + f(r) + " 0 0 " + sweep + " " + f(x) + " " + f(y) : " L " + f(x) + " " + f(y) }
    function ln(x, y) { return " L " + f(x) + " " + f(y) }

    // The outline inset by `d`, moved down by `dy` (the hard shadow); `fl` false leaves the fillets out (the shadow).
    // Clockwise: the start side (left to right), the outer side (down), the end side (right to left), the inner side (up).
    function path(d, fl, dy) {
        if (!shown) return ""
        var X0 = x0 + d, X1 = x1 - d, Y0 = y0 + d + dy, Y1 = y1 - d + dy
        var Et = y0 + dy, Eb = y1 + dy, T = y0 - k + d + dy, B = y1 + k - d + dy, S = x1, R = x1 + k - d
        if (X1 - X0 < 1) return ""
        if ((openT ? Et : Y0) >= (openB ? Eb : Y1) - 1) return ""
        var tl = Math.max(0, rTL - d), tr = Math.max(0, rTR - d), br = Math.max(0, rBR - d), bl = Math.max(0, rBL - d)
        var a = fl ? fTi : 0, b = fl ? fTo : 0, c = fl ? fBo : 0, e = fl ? fBi : 0, g = fl ? fOt : 0, h = fl ? fOb : 0
        var s
        // The start side.
        if (openT) {
            s = "M " + f(X0) + " " + f(T)
            if (openO) s += ln(R, T)
            else {
                s += ln(X1, T)
                if (b > 0.5) {
                    if (ruled) s += ln(X1, Et - d) + ln(x1 + b, Et - d) + arc(b + d, 0, X1, Et + b)
                    else s += ln(X1, Et) + ln(X1 + b, Et) + arc(b, 0, X1, Et + b)
                }
            }
        } else {
            s = "M " + f(X0) + " " + f(Y0 + tl) + arc(tl, 1, X0 + tl, Y0)
            if (openO) {
                if (g > 0.5) {
                    if (ruled) s += ln(S - g, Y0) + arc(g + d, 0, S + d, y0 - g + dy) + ln(R, y0 - g + dy)
                    else s += ln(S - g, Y0) + arc(g, 0, S, Y0 - g) + ln(R, Y0 - g)
                } else s += ln(R, Y0)
            } else s += ln(X1 - tr, Y0) + arc(tr, 1, X1, Y0 + tr)
        }
        // The outer side.
        if (openO) {
            if (openB) s += ln(R, B)
            else if (h > 0.5) {
                if (ruled) s += ln(R, y1 + h + dy) + ln(S + d, y1 + h + dy) + arc(h + d, 0, S - h, Y1)
                else s += ln(R, Y1 + h) + ln(S, Y1 + h) + arc(h, 0, S - h, Y1)
            } else s += ln(R, Y1)
        } else if (openB) {
            if (c > 0.5) {
                if (ruled) s += ln(X1, Eb - c) + arc(c + d, 0, x1 + c, Eb + d) + ln(X1, Eb + d)
                else s += ln(X1, Eb - c) + arc(c, 0, X1 + c, Eb) + ln(X1, Eb)
            }
            s += ln(X1, B)
        } else s += ln(X1, Y1 - br) + arc(br, 1, X1 - br, Y1)
        // The end side.
        if (openB) {
            s += ln(X0, B)
            if (e > 0.5) {
                if (ruled) s += ln(X0, Eb + d) + ln(x0 - e, Eb + d) + arc(e + d, 0, X0, Eb - e)
                else s += ln(X0, Eb) + ln(X0 - e, Eb) + arc(e, 0, X0, Eb - e)
            }
        } else s += ln(X0 + bl, Y1) + arc(bl, 1, X0, Y1 - bl)
        // The inner side.
        if (openT) {
            if (a > 0.5) {
                if (ruled) s += ln(X0, Et + a) + arc(a + d, 0, x0 - a, Et - d) + ln(X0, Et - d)
                else s += ln(X0, Et + a) + arc(a, 0, X0 - a, Et) + ln(X0, Et)
            }
            s += ln(X0, T)
        } else s += ln(X0, Y0 + tl)
        return Corner.squircled(s + " Z", Theme.squircle)
    }
    function band(a, b) { var p = path(a, true, 0), q = path(b, true, 0); return p === "" ? "" : p + " " + q }

    // The fill's own path (inside the outline and the ring): the caller clips the column's relief to it.
    readonly property string fillPath: shown ? path(ow + gw, true, 0) : ""
    // The body's rect without the fillets (the soft shadow's).
    readonly property rect bodyRect: Qt.rect(x0, y0, bw, bh)
    // The body's corners as they lie on screen (the caller's mirroring undone), for the window's blur region: it follows
    // the body's rounding, never past the outline (I276); the fillets beyond are left out.
    readonly property real sTL: flipY ? (flipX ? rBR : rBL) : (flipX ? rTR : rTL)
    readonly property real sTR: flipY ? (flipX ? rBL : rBR) : (flipX ? rTL : rTR)
    readonly property real sBL: flipY ? (flipX ? rTR : rTL) : (flipX ? rBR : rBL)
    readonly property real sBR: flipY ? (flipX ? rTL : rTR) : (flipX ? rBL : rBR)

    // K62: with a pen in effect the pen draws the outline along its centre line (one closed line; the open sides lie
    // past the neighbour's edge).
    readonly property bool penOn: ruled ? Theme.framePen : Theme.penOutline
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
            line: sh.ruled ? Theme.framePenLine : Theme.penLine
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
