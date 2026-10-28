import QtQuick
import QtQuick.Shapes
import Quickshell
import "../../core"
import ".."
import "../pen.js" as Pen
import "../../core/corner.js" as Corner

// The island's one shape while it morphs (W21; Capsule's single morphing capsule, Vitreus's liquid neck). Drawn in a top
// bar's frame; the Stage mirrors the whole item for a bottom bar (`flip`: the hard shadow still falls towards the screen's
// bottom then). Two topologies, picked by the Stage from tokens (rule 4):
// - strip (`joined` false: the bar is one strip, flat and line chrome): a rounded rect from (x0, y0), w x h, whose top
//   lies inside the bar; where its side crosses the bar's edge (`edgeY`) it is joined to the strip by concave fillets of
//   up to `neck` px, so the card grows out of the bar rather than floating under it. Where the bar rules its edge (an
//   outline token: line chrome) the card hangs from the rule, whose line runs round the fillets into the card's sides
//   (`hangs`, W30).
// - joined (`joined` true: the bar's groups float as blocks, keycap and soft chrome; I115): the head is the island's own
//   bar block (hx0, hy0, hw x hh, corners hr), the body (x0, y0, w x h) grows out from under it, and a neck with concave
//   fillets of up to `neckF` px joins them. One closed outline round head, neck and body, so the keycap's outline, ring
//   and hard shadow follow the joined shape.
// Every layer is one closed path; the outline and the ring are bands (the path less its inset, odd-even), so no layer
// lies under another and the fill may be translucent (I114: Theme.panel). Chrome comes from tokens only: the outline
// `Theme.outlineW` in `Theme.outlineColor` (flat: a 1 px `Theme.outline` hairline), the ring `Theme.ringW` x `ringScale`,
// the hard shadow along `Theme.sinkX/Y` (K67; `Theme.shadowDy` straight down by default). A soft shadow is the Stage's (RectangularShadows under head and body). A path is
// rebuilt only when a number changes: nothing runs while it stands (Ma).
// W34 additions (all optional, defaults keep the above; see the properties): `headless` (grow out of the bar from under a
// widget that stays drawn — hanging from a strip's edge, or budding from a block by a neck that can let go: `neckCx`,
// `attach`), `neckScale` (the landing wobble), `headFill` (I160), `fade` (I161), `barCx` (an item not centred on its bar).
// Its springs live in MorphSprings (same folder), which a surface can reuse with it.
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
    // The joined topology (see the header): the head's rect and corners, and the neck's fillet.
    property bool joined: false
    property real hx0: 0
    property real hy0: 0
    property real hw: 0
    property real hh: 0
    property real hr: 0
    property real neckF: 0
    // W34 (docs/ux/motion.md) — all optional; the defaults draw exactly what the island drew before:
    // `headless`: no head — the shape grows out of the bar from under a widget that stays drawn. On a strip it hangs from
    //   the strip's edge (`edgeY`) by its neck fillets, its outline one open U band from one fillet's tip to the other's
    //   (as `hangs`, on any strip, with no rule copy and no opening of the bar's rule). Joined, `edgeY` is the foot of the
    //   widget's block (its face's bottom): a neck centred on `neckCx`, `attach` (0..1) of its full width, with concave
    //   fillets of `neckF` at both ends, joins the body below to the block, the outline open where it meets it and the
    //   fill reaching `ow` px up over the block's own outline there; `attach` 0 leaves the body free (it has travelled
    //   away from the widget).
    // `neckScale`: the neck's fillets scaled (the landing wobble, MorphSprings.neckScale).
    // `headFill`: the fill above `edgeY` on a strip with a head (I160: a translucent head over the bar's translucent strip
    //   is drawn lighter, so the two make one layer); the default is `fill`, one fill.
    // `fade`: the shape's opacity without the bar's rule copy (I161: a view with its own chrome takes over while the rule
    //   must stay whole under the box the bar has opened).
    property bool headless: false
    property real neckCx: x0 + w / 2
    property real attach: 1
    property real neckScale: 1
    property color headFill: fill
    property real fade: 1

    readonly property real x1: x0 + w
    readonly property real y1: y0 + h
    // The neck forms once the bottom has room below the bar's edge for the fillet and the bottom corners.
    readonly property real rb: Math.max(0, Math.min(rBot, w / 2, h / 2))
    readonly property real rt: Math.max(0, Math.min(rTop, w / 2, h / 2, Math.max(0, edgeY - y0)))
    readonly property real n: Math.max(0, Math.min(neck * neckScale, y1 - edgeY - rb, (y1 - edgeY) / 2))
    function fa(c, a) { return Qt.rgba(c.r, c.g, c.b, c.a * a) }
    readonly property real ow: Theme.outlineW > 0 ? Theme.outlineW : 1
    readonly property color oc: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
    readonly property real gw: Theme.ringW * ringScale
    // The hard shadow's vector (K67): `sd` down the path (mirrored with the frame), `Theme.sinkX` across by moving its layer.
    readonly property real sd: (flip ? -1 : 1) * Theme.sinkY
    readonly property bool casts: Theme.sinkX !== 0 || Theme.sinkY !== 0

    function f(v) { return Math.round(v * 100) / 100 }
    function arc(r, sweep, x, y) { return r > 0.05 ? " A " + f(r) + " " + f(r) + " 0 0 " + sweep + " " + f(x) + " " + f(y) : " L " + f(x) + " " + f(y) }
    function rrect(X0, Y0, X1, Y1, r) {
        if (X1 - X0 < 1 || Y1 - Y0 < 1) return ""
        r = Math.max(0, Math.min(r, (X1 - X0) / 2, (Y1 - Y0) / 2))
        return "M " + f(X0 + r) + " " + f(Y0) + " L " + f(X1 - r) + " " + f(Y0) + arc(r, 1, X1, Y0 + r)
            + " L " + f(X1) + " " + f(Y1 - r) + arc(r, 1, X1 - r, Y1) + " L " + f(X0 + r) + " " + f(Y1) + arc(r, 1, X0, Y1 - r)
            + " L " + f(X0) + " " + f(Y0 + r) + arc(r, 1, X0 + r, Y0) + " Z"
    }
    // A rect with its own top and bottom corner radii.
    function rrect2(X0, Y0, X1, Y1, t, b) {
        if (X1 - X0 < 1 || Y1 - Y0 < 1) return ""
        t = Math.min(t, (X1 - X0) / 2, (Y1 - Y0) / 2); b = Math.min(b, (X1 - X0) / 2, (Y1 - Y0) / 2)
        return "M " + f(X0 + t) + " " + f(Y0) + " L " + f(X1 - t) + " " + f(Y0) + arc(t, 1, X1, Y0 + t)
            + " L " + f(X1) + " " + f(Y1 - b) + arc(b, 1, X1 - b, Y1) + " L " + f(X0 + b) + " " + f(Y1) + arc(b, 1, X0, Y1 - b)
            + " L " + f(X0) + " " + f(Y0 + t) + arc(t, 1, X0 + t, Y0) + " Z"
    }
    // The strip topology's outline inset by `d` (the sides and the free edges move in; the fillets keep their radius, so
    // the rings thin out towards the bar's edge and melt into it). `neckOn` false: the plain body (the shadow).
    function stripPath(d, neckOn, dy) {
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
    // The joined topology's outline inset by `d`, moved down by `dy`: clockwise round the head, down the neck's right
    // side, round the body, up the neck's left side. The neck is centred on the head and kept inside both straight edges.
    function joinedPath(d, dy) {
        var HX0 = hx0 + d, HX1 = hx0 + hw - d, HY0 = hy0 + d + dy, HY1 = hy0 + hh - d + dy
        var BX0 = x0 + d, BX1 = x1 - d, BY0 = y0 + d + dy, BY1 = y1 - d + dy
        var head = rrect(HX0, HY0, HX1, HY1, hr - d)
        if (head === "") return ""
        if (BX1 - BX0 < 1 || BY1 - BY0 < 1) return head
        var r = Math.max(0, Math.min(hr - d, (HX1 - HX0) / 2, (HY1 - HY0) / 2))
        var bt = Math.max(0, Math.min(rTop - d, (BX1 - BX0) / 2, (BY1 - BY0) / 2))
        var bb = Math.max(0, Math.min(rBot - d, (BX1 - BX0) / 2, (BY1 - BY0) / 2))
        var gap = BY0 - HY1
        var fl = Math.max(0, Math.min(neckF, gap / 2))
        var cx = (HX0 + HX1) / 2, hhw = (HX1 - HX0) / 2
        var hn = Math.min(Math.max(10, hhw * 0.5), hhw - r - fl, cx - BX0 - bt - fl, BX1 - bt - fl - cx)
        // No room for a neck (a body that has not grown past the head, or a head too small): head and body as they are.
        if (gap < -0.5 || hn < 2) return head + " " + rrect(BX0, BY0, BX1, BY1, bt)
        var s = "M " + f(HX0 + r) + " " + f(HY0) + " L " + f(HX1 - r) + " " + f(HY0) + arc(r, 1, HX1, HY0 + r)
        s += " L " + f(HX1) + " " + f(HY1 - r) + arc(r, 1, HX1 - r, HY1)
        s += " L " + f(cx + hn + fl) + " " + f(HY1) + arc(fl, 0, cx + hn, HY1 + fl)
        s += " L " + f(cx + hn) + " " + f(BY0 - fl) + arc(fl, 0, cx + hn + fl, BY0)
        s += " L " + f(BX1 - bt) + " " + f(BY0) + arc(bt, 1, BX1, BY0 + bt)
        s += " L " + f(BX1) + " " + f(BY1 - bb) + arc(bb, 1, BX1 - bb, BY1)
        s += " L " + f(BX0 + bb) + " " + f(BY1) + arc(bb, 1, BX0, BY1 - bb)
        s += " L " + f(BX0) + " " + f(BY0 + bt) + arc(bt, 1, BX0 + bt, BY0)
        s += " L " + f(cx - hn - fl) + " " + f(BY0) + arc(fl, 0, cx - hn, BY0 - fl)
        s += " L " + f(cx - hn) + " " + f(HY1 + fl) + arc(fl, 0, cx - hn - fl, HY1)
        s += " L " + f(HX0 + r) + " " + f(HY1) + arc(r, 1, HX0, HY1 - r)
        s += " L " + f(HX0) + " " + f(HY0 + r) + arc(r, 1, HX0 + r, HY0) + " Z"
        return s
    }
    // A ruled strip (line chrome: an outline token, the bar rules its strip's edge in it; W30): the card hangs from the
    // bar's rule rather than standing in front of it. Its outline is the rule itself — along the rule's band (edgeY − ow …
    // edgeY), round the concave fillet (concentric: radius n outside, n + ow inside, so the band keeps its width; mitred
    // when square) and down the sides — and the head, the part inside the bar, loses its own outline as the card grows
    // (`opened`: 0 the pill's outlined box, 1 once the bottom is a bar's height past the edge; the head's inset thins to
    // nothing). Open, a band is one U-shaped polygon from one fillet's top round the card to the other's (no head, no
    // coincident edges, which would leave an anti-aliased trace). The rule up to the fillets is the shape's own too, and
    // the bar leaves its rule out under the shape's box (rulePath, IslandGeom.setOpening), so a translucent fill never
    // shows the rule through it and the card's side and the rule meet as one line in every frame, morphing or not.
    readonly property bool ruled: Theme.outlineW > 0
    // A headless shape on a strip hangs from the strip's edge on any strip (W34), always open.
    readonly property bool hangs: !joined && (headless ? y1 - edgeY > 0.5 : ruled && y1 - edgeY > rb + 1)
    readonly property real opened: hangs ? (headless ? 1 : Math.max(0, Math.min(1, (y1 - edgeY - rb) / Math.max(1, edgeY)))) : 0
    // Test only (KURASHI_ISLAND_DEBUG=1, frontend/test-island-join.sh): every change of `opened` with the card's foot, so
    // the pixel check can tell which grabbed frames caught the card mid-morph.
    readonly property bool debugLog: Quickshell.env("KURASHI_ISLAND_DEBUG") === "1"
    onOpenedChanged: if (debugLog && visible) console.log("island-shape opened=" + opened.toFixed(3) + " y1=" + y1.toFixed(1))
    // The hanging card's contour inset by `d`, from the right fillet's top (x1 + n, edgeY − min(d, ow)) round the card to
    // the left fillet's top; `back` walks it the other way. The fillet is concentric with the outside one (radius n + d),
    // a square corner is mitred; a ring's inset (d > ow) runs on below the fillet.
    function hangContour(d, dy, back) {
        var dd = Math.min(d, ow), E = edgeY + dy, rnd = n > 0.5
        var X0 = x0 + d, X1 = x1 - d, Y1 = y1 - d + dy, b = Math.max(0, rb - d)
        var yF = rnd ? E + n : E - dd, yN = yF + (d - dd)
        var s = ""
        if (!back) {
            s += rnd ? arc(n + dd, 0, x1 - dd, E + n) : " L " + f(x1 - dd) + " " + f(E - dd)
            s += " L " + f(X1) + " " + f(yN) + " L " + f(X1) + " " + f(Y1 - b) + arc(b, 1, X1 - b, Y1)
            s += " L " + f(X0 + b) + " " + f(Y1) + arc(b, 1, X0, Y1 - b) + " L " + f(X0) + " " + f(yN) + " L " + f(x0 + dd) + " " + f(yF)
            s += rnd ? arc(n + dd, 0, x0 - n, E - dd) : " L " + f(x0) + " " + f(E - dd)
        } else {
            s += rnd ? arc(n + dd, 1, x0 + dd, E + n) : " L " + f(x0 + dd) + " " + f(E - dd)
            s += " L " + f(X0) + " " + f(yN) + " L " + f(X0) + " " + f(Y1 - b) + arc(b, 0, X0 + b, Y1)
            s += " L " + f(X1 - b) + " " + f(Y1) + arc(b, 0, X1, Y1 - b) + " L " + f(X1) + " " + f(yN) + " L " + f(x1 - dd) + " " + f(yF)
            s += rnd ? arc(n + dd, 1, x1 + n, E - dd) : " L " + f(x1) + " " + f(E - dd)
        }
        return s
    }
    // The whole hanging shape inset by `d` (the fill, and the bands while the head still has its outline): the head inside
    // the bar (inset by d·(1 − opened)), along the rule's top to the right fillet, round the card, back to the head.
    function openPath(d, dy) {
        var hd = d * (1 - opened), dd = Math.min(d, ow)
        var H0 = x0 + hd, H1 = x1 - hd, Y0 = y0 + hd + dy
        var E = edgeY + dy, R = E - ow
        var t = Math.max(0, rt - hd)
        if (x1 - x0 - 2 * d < 1 || H1 - H0 < 1) return ""
        var s = "M " + f(H0 + t) + " " + f(Y0) + " L " + f(H1 - t) + " " + f(Y0) + arc(t, 1, H1, Y0 + t) + " L " + f(H1) + " " + f(R)
        s += " L " + f(x1 + n) + " " + f(R) + " L " + f(x1 + n) + " " + f(E - dd) + hangContour(d, dy, false)
        s += " L " + f(x0 - n) + " " + f(R) + " L " + f(H0) + " " + f(R) + " L " + f(H0) + " " + f(Y0 + t) + arc(t, 1, H0 + t, Y0)
        return s + " Z"
    }
    // W34, headless on a strip: the fill is the card and its fillets, and the rule's band between the fillets' tips (the
    // card is open to the bar there; the bar's own rule and strip go on outside the tips).
    function hangFill(d, dy) {
        if (x1 - x0 - 2 * d < 1) return ""
        var E = edgeY + dy, dd = Math.min(d, ow)
        return "M " + f(x0 - n) + " " + f(E - ow) + " L " + f(x1 + n) + " " + f(E - ow) + " L " + f(x1 + n) + " " + f(E - dd)
            + hangContour(d, dy, false) + " Z"
    }
    // W34, headless and joined: the neck's half width, centre and fillets (0 half width: no neck, the body is free).
    readonly property real budGap: y0 - edgeY
    readonly property real budFl: Math.max(0, Math.min(neckF * neckScale, budGap / 2))
    // The neck takes what the body's width leaves it (a body as narrow as the widget hangs from the block by its whole
    // top); the body's top corners round only where the neck leaves room.
    readonly property real budHalf: Math.min(neckCx - x0, x1 - neckCx)
    readonly property real budHn: {
        if (budGap < -0.5 || h < 2 || attach <= 0.01) return 0
        return Math.max(0, Math.min(Math.max(10, neckF * 1.5) * Math.min(1, attach), budHalf - budFl - 1))
    }
    readonly property real budBt: Math.max(0, Math.min(rTop, w / 2, h / 2, budHalf - budHn - budFl))
    // The bud's contour inset by `d` from the right tip of the neck's top fillet (neckCx + hn + fl, edgeY − min(d, ow)),
    // down the neck, round the body and up to the left tip; the fillets are concentric with the outside ones.
    function budContour(d, dy) {
        var dd = Math.min(d, ow), E = edgeY + dy, fl = budFl, fb = budFl, hn = budHn, cx = neckCx
        var BX0 = x0 + d, BX1 = x1 - d, BY0 = y0 + d + dy, BY1 = y1 - d + dy
        var bt = Math.max(0, budBt - d), bb = Math.max(0, Math.min(rBot - d, (BX1 - BX0) / 2, (BY1 - BY0) / 2))
        var yB = y0 + dy - fb, yN = Math.min(E + fl + (d - dd), yB)
        var s = arc(fl + dd, 0, cx + hn - dd, E + fl) + " L " + f(cx + hn - d) + " " + f(yN)
        s += " L " + f(cx + hn - d) + " " + f(yB) + arc(fb + d, 0, cx + hn + fb, BY0)
        s += " L " + f(BX1 - bt) + " " + f(BY0) + arc(bt, 1, BX1, BY0 + bt)
        s += " L " + f(BX1) + " " + f(BY1 - bb) + arc(bb, 1, BX1 - bb, BY1)
        s += " L " + f(BX0 + bb) + " " + f(BY1) + arc(bb, 1, BX0, BY1 - bb)
        s += " L " + f(BX0) + " " + f(BY0 + bt) + arc(bt, 1, BX0 + bt, BY0)
        s += " L " + f(cx - hn - fb) + " " + f(BY0) + arc(fb + d, 0, cx - hn + d, yB)
        s += " L " + f(cx - hn + d) + " " + f(yN) + " L " + f(cx - hn + dd) + " " + f(E + fl)
        s += arc(fl + dd, 0, cx - hn - fl, E - dd)
        return s
    }
    // The bud closed: along the block's foot (`top` = edgeY + dy, the band's), or `ow` up into the block (the fill's).
    function budPath(d, dy, top) {
        var BX0 = x0 + d, BX1 = x1 - d, BY0 = y0 + d + dy, BY1 = y1 - d + dy
        if (BX1 - BX0 < 1 || BY1 - BY0 < 1) return ""
        if (budHn <= 0) return rrect(BX0, BY0, BX1, BY1, Math.max(0, Math.min(rTop, rBot) - d))
        // A neck thinner than this inset has no inside: the inset is the body's alone (a thin neck is all outline).
        if (budHn - d < 0.5) return rrect2(BX0, BY0, BX1, BY1, Math.max(0, budBt - d),
            Math.max(0, Math.min(rBot - d, (BX1 - BX0) / 2, (BY1 - BY0) / 2)))
        var dd = Math.min(d, ow), E = edgeY + dy, tl = neckCx - budHn - budFl, tr = neckCx + budHn + budFl
        return "M " + f(tr) + " " + f(E - dd) + budContour(d, dy) + " L " + f(tl) + " " + f(top) + " L " + f(tr) + " " + f(top) + " Z"
    }
    function path(d, dy) {
        if (joined) return headless ? budPath(d, dy, edgeY + dy - ow) : joinedPath(d, dy)
        if (headless) return hangs ? hangFill(d, dy) : ""
        return hangs ? openPath(d, dy) : stripPath(d, true, dy)
    }
    // A band between the insets a and b (the outline: 0 … ow; the ring: ow … ow + gw), for odd-even filling.
    function band(a, b) {
        if (joined && headless) return budHn > 0 ? budPath(a, 0, edgeY) + " " + budPath(b, 0, edgeY) : path(a, 0) + " " + path(b, 0)
        if (!hangs || opened < 1) return path(a, 0) + " " + path(b, 0)
        if (x1 - x0 - 2 * b < 1) return ""
        return "M " + f(x1 + n) + " " + f(edgeY - Math.min(a, ow)) + hangContour(a, 0, false)
            + " L " + f(x0 - n) + " " + f(edgeY - Math.min(b, ow)) + hangContour(b, 0, true) + " Z"
    }
    // The bar and the shape are two surfaces whose frames are not presented together: an opening that followed the card
    // frame by frame lagged it (a growing card's fillet stood off the rule's end, a shrinking one left the rule under the
    // card). So under a ruled strip the shape draws the bar's rule itself across its whole box — the rule's band, in the
    // outline (opaque under line chrome), level with the bar's — in every state: whole under a pill that has not reached
    // it (beneath the fill, as the bar's rule was), and while the card hangs from it, from the box's edges to the fillets'
    // tops (1 px into the fillet's band, so the two never leave a seam), never under the card. The bar opens its rule
    // under the box (2 px inside its edges, an overlap), which stands still while the box does: it changes only when the
    // shape comes out or goes (IslandGeom.takenOn) or the box is resized, never while the card morphs.
    readonly property bool ruledStrip: !joined && ruled && !headless
    function ruleRect(a, b) {
        var R = edgeY - ow
        return b - a < 0.5 ? "" : " M " + f(a) + " " + f(R) + " L " + f(b) + " " + f(R) + " L " + f(b) + " " + f(edgeY) + " L " + f(a) + " " + f(edgeY) + " Z"
    }
    function rulePath() {
        if (!ruledStrip) return ""
        return hangs ? ruleRect(0, x0 - n + 1) + ruleRect(x1 + n - 1, width) : ruleRect(0, width)
    }
    // Where the bar's rule opens under the shape, from the bar's centre (`barCx`, in this item's px: its centre unless
    // the owner places the item off the bar's centre, W34); 0, 0 while the shape is not out on a ruled strip. Reported
    // only on a change.
    property real barCx: width / 2
    readonly property real openL: ruledStrip && visible && width > 8 ? -Math.floor(barCx) + 2 : 0
    readonly property real openR: ruledStrip && visible && width > 8 ? Math.floor(width - barCx) - 2 : 0
    onOpenLChanged: IslandGeom.setOpening(openL, openR)
    onOpenRChanged: IslandGeom.setOpening(openL, openR)
    Component.onDestruction: IslandGeom.setOpening(0, 0)

    // The fill's own path (inside the outline and the ring): the Stage clips the island's relief to it (I168), so the
    // material covers head, neck fillets and body and nothing else.
    readonly property string fillPath: visible ? Corner.squircled(path(ow + gw, 0), Theme.squircle) : ""

    // K62: with a pen in effect the pen draws the outline band and the rule the shape carries, along their centre lines
    // (the same contours at half the outline's inset): one closed line round head, neck and body — or, hanging from a
    // ruled strip, one open line from the box's left edge along the rule, round the card and back along the rule to its
    // right edge, so it meets the bar's own (pen) rule; the head's outline thins out as the card opens. The ring, the
    // fill and its relief mask (`fillPath`) are untouched.
    readonly property bool penOn: Theme.penOutline
    function penPaths() {
        if (!visible || !penOn) return []
        var c = ow / 2, out = []
        function add(d, width, closed) {
            var subs = Pen.svgPaths(Corner.squircled(d, Theme.squircle))
            for (var i = 0; i < subs.length; i++)
                out.push({ points: subs[i].pts, closed: closed === undefined ? subs[i].closed : closed, width: width })
        }
        if (joined && headless) {
            if (budHn > 0) add("M " + f(neckCx + budHn + budFl) + " " + f(edgeY - c) + budContour(c, 0), ow, false)
            else add(budPath(c, 0, 0), ow)
        } else if (joined) {
            add(joinedPath(c, 0), ow)
        } else if (headless) {
            if (hangs) add("M " + f(x1 + n) + " " + f(edgeY - c) + hangContour(c, 0, false), ow, false)
        } else if (!hangs) {
            add(stripPath(c, true, 0), ow)
            if (ruledStrip) add("M 0 " + f(edgeY - c) + " L " + f(width) + " " + f(edgeY - c), ow, false)
        } else {
            var E = edgeY - c
            add("M " + f(width) + " " + f(E) + " L " + f(x1 + n) + " " + f(E) + hangContour(c, 0, false) + " L 0 " + f(E), ow, false)
            if (opened < 0.99) {
                var X0 = x0 + c, X1 = x1 - c, Y0 = y0 + c, R = edgeY - ow, t = Math.max(0, rt - c)
                if (R - Y0 > t + 0.5)
                    add("M " + f(X0) + " " + f(R) + " L " + f(X0) + " " + f(Y0 + t) + arc(t, 1, X0 + t, Y0) + " L " + f(X1 - t)
                        + " " + f(Y0) + arc(t, 1, X1, Y0 + t) + " L " + f(X1) + " " + f(R), ow * (1 - opened), false)
            }
        }
        return out
    }
    Loader {
        anchors.fill: parent
        active: sh.penOn && sh.visible
        opacity: sh.fade
        sourceComponent: PenOutline {
            color: sh.oc
            lineWidth: sh.ow
            seed: 0x15A4D
            paths: sh.penPaths()
        }
    }
    // I160: on a strip with a head, the fill above the bar's edge in `headFill` and below it in `fill`, each cut by a
    // scissor at the edge (the edge is the bar's own, so the seam is the bar's).
    readonly property bool splitFill: !joined && !headless && !Qt.colorEqual(headFill, fill)
    Item {
        visible: sh.splitFill && sh.visible
        width: sh.width
        height: Math.max(0, sh.edgeY)
        clip: true
        Shape {
            width: sh.width
            height: sh.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: sh.fa(sh.headFill, sh.fade)
                PathSvg { path: sh.splitFill ? sh.fillPath : "" }
            }
        }
    }
    Item {
        visible: sh.splitFill && sh.visible
        y: Math.max(0, sh.edgeY)
        width: sh.width
        height: Math.max(0, sh.height - y)
        clip: true
        Shape {
            y: -parent.y
            width: sh.width
            height: sh.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: sh.fa(sh.fill, sh.fade)
                PathSvg { path: sh.splitFill ? sh.fillPath : "" }
            }
        }
    }

    preferredRendererType: Shape.CurveRenderer
    // The hard shadow: the outline moved along the shadow vector, in a layer of its own under the shape's (z −1) so the
    // vector's x is the layer's place and no path is rebuilt for it.
    Shape {
        z: -1
        x: Theme.sinkX
        width: sh.width
        height: sh.height
        visible: sh.visible && sh.casts
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: sh.casts ? sh.fa(Theme.line, sh.fade) : "transparent"
            PathSvg { path: sh.visible && sh.casts ? Corner.squircled(sh.joined ? sh.path(0, sh.sd) : sh.stripPath(0, false, sh.sd), Theme.squircle) : "" }
        }
    }
    // The bar's rule, drawn by the shape (a ruled strip only; see rulePath), under the outline and the fill.
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: sh.ruledStrip && !sh.penOn ? sh.oc : "transparent"
        PathSvg { path: sh.visible && !sh.penOn ? Corner.squircled(sh.rulePath(), Theme.squircle) : "" }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillColor: sh.penOn ? "transparent" : sh.fa(sh.oc, sh.fade)
        PathSvg { path: sh.visible && !sh.penOn ? Corner.squircled(sh.band(0, sh.ow), Theme.squircle) : "" }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillColor: sh.gw > 0 ? sh.fa(Theme.ring, sh.fade) : "transparent"
        PathSvg { path: sh.visible && sh.gw > 0 ? Corner.squircled(sh.band(sh.ow, sh.ow + sh.gw), Theme.squircle) : "" }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: sh.splitFill ? "transparent" : sh.fa(sh.fill, sh.fade)
        PathSvg { path: sh.splitFill ? "" : sh.fillPath }
    }
}
