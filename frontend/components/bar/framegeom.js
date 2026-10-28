.pragma library

// The screen frame's geometry (K71, docs/ux/frame.md), shared by the frame's strips (surfaces/Frame.qml) and the docked bar
// that carries its edge's strip (row 492 b, surfaces/Bar.qml): both draw from the same `runtime.layout` entry with the same
// rules, so the strip one of them leaves out is exactly the one the other draws. Pure functions, output logical px.

function edgeOf(lay, e) { return (lay && lay.edges && lay.edges[e]) || {} }
function band(lay, e) { var f = lay ? lay.frame : null; return f && f.on && f.band ? (f.band[e] || 0) : 0 }
// A bar stands flush on edge `e` of a framed output and is the band there: the daemon's rule (kurashi-layout `docked`,
// PROTOCOL §3.1, rows 481 a, 510) — any visibility but hidden (a hover bar's place stays the band's; a hidden bar is not
// the band: it comes out over it, and the frame draws that edge's strip). The layout then says `band.<e>` 0 and, while
// the frame reserves, `holder: "bar"`.
function docked(lay, e) {
    var ed = edgeOf(lay, e), f = (lay && lay.frame) || {}
    return f.on === true && ed.bar === true && ed.draw !== "floating" && ed.visibility !== "hidden"
}
// The zone the frame keeps on each edge (0: none) — held by its strip (`holder: "frame"`), or by the docked bar that
// carries that strip (`holder: "bar"`, row 510): the side strips that hold a zone are placed inside the top and bottom
// ones (mapped first), whichever window holds them.
function zones(lay) {
    var z = {}, es = ["top", "bottom", "left", "right"], on = !!(lay && lay.frame && lay.frame.on === true)
    for (var i = 0; i < es.length; i++) {
        var ed = edgeOf(lay, es[i])
        var held = ed.holder === "frame" || (ed.holder === "bar" && docked(lay, es[i]))
        z[es[i]] = on && held && (ed.reserve || 0) > 0 ? Math.round(ed.reserve) : 0
    }
    return z
}

// Points along a quarter circle (centre, radius, from angle a0 to a1, radians; screen axes, y down).
function arc(cx, cy, rad, a0, a1) {
    var n = Math.max(6, Math.ceil(rad / 2)), pts = []
    for (var i = 0; i <= n; i++) {
        var a = a0 + (a1 - a0) * i / n
        pts.push({ x: cx + rad * Math.cos(a), y: cy + rad * Math.sin(a) })
    }
    return pts
}

// Everything the pieces depend on: the output's size, the cut's edges (`o`: band + docked bar), the bands (`b`), the inner
// radius, the rule's width and the zones (`z`).
function geometry(lay, barH, sw, sh, ow, z) {
    var f = (lay && lay.frame) || {}
    var b = { top: band(lay, "top"), bottom: band(lay, "bottom"), left: band(lay, "left"), right: band(lay, "right") }
    var o = {
        top: b.top + (docked(lay, "top") ? barH : 0),
        bottom: b.bottom + (docked(lay, "bottom") ? barH : 0),
        left: b.left + (docked(lay, "left") ? barH : 0),
        right: b.right + (docked(lay, "right") ? barH : 0)
    }
    var dk = { top: docked(lay, "top"), bottom: docked(lay, "bottom"), left: docked(lay, "left"), right: docked(lay, "right") }
    return { sw: sw, sh: sh, o: o, b: b, dk: dk, r: Math.max(0, Math.round(f.radius || 0)), ow: ow, z: z }
}
// Where a side strip starts and ends: never above the zones the compositor already placed it inside (a holder is placed
// within the top and bottom holders' zones, mapped before it).
function sideFrom(g, e) { return g.z[e] > 0 && g.z.top > 0 ? g.z.top : 0 }
function sideTo(g, e) { return g.z[e] > 0 && g.z.bottom > 0 ? g.z.bottom : 0 }

// The top or bottom strip's pieces (`top` true for the top one): its depth `d` and its fills, fillets, rule pieces and
// arcs. It draws its band, the side bands from the cut's edge down to the end of the fillets (or on to where the side
// strip starts when this edge's zone is deeper than that: a floating bar's reserve), and the inner fillets.
function across(g, top) {
    var W = g.sw, H = g.sh, o = g.o, b = g.b, r = g.r, ow = g.ow
    var e = top ? "top" : "bottom"
    var reachL = Math.max(o[e] + r, top ? sideFrom(g, "left") : sideTo(g, "left"))
    var reachR = Math.max(o[e] + r, top ? sideFrom(g, "right") : sideTo(g, "right"))
    var d = Math.max(o[e] + r, b.left > 0 ? reachL : 0, b.right > 0 ? reachR : 0), y0 = top ? 0 : H - d
    var bw = b[e]
    var fills = [], fillets = [], rules = [], arcs = []
    // The band runs the whole width: the horizontal strips own the corners (a docked side bar runs between them, row 511).
    if (bw > 0) fills.push({ x: 0, y: top ? 0 : H - bw, w: W, h: bw })
    // The side columns this strip draws: a side's band down to where its strip starts; a docked side bar's thickness, 0
    // deep at rest (its window starts at this strip's cut), that grows while this edge's bar slides (the corner between
    // the two bars stays sheet).
    var dk = g.dk || {}
    var cols = [dk.left ? [o.left, o[e], 0] : [b.left, reachL, 0], dk.right ? [o.right, o[e], W - o.right] : [b.right, reachR, W - b.right]]
    for (var i = 0; i < 2; i++) {
        var cw = cols[i][0], reach = cols[i][1], cx = cols[i][2], bar = i === 0 ? dk.left : dk.right
        if (cw <= 0 || (reach <= o[e] && !bar)) continue
        // (`grow`: its end at the cut follows a sliding bar's moving edge on this strip's edge, FramePieces `lift*`.)
        fills.push({ x: cx, y: top ? o[e] : H - reach, w: cw, h: reach - o[e], grow: e })
        // Past the fillet the side's rule runs on in this strip (0 long at rest where the side strip starts at the fillet's
        // end: it is there for a carrying bar's lift, which brings the fillet nearer the edge than the side strip starts).
        var past = Math.max(0, reach - o[e] - r)
        if (ow > 0)
            rules.push({ x: i === 0 ? cw - ow : cx, y: top ? o[e] + r : H - reach, w: ow, h: past, grow: e, vert: true })
    }
    var edgeY = top ? o.top : H - o.bottom
    if (r > 0) {
        // (`c`: the corner it hangs in — it moves with a sliding bar on either of that corner's edges.)
        fillets.push(top ? { x: o.left, y: o.top, turn: 0, c: "tl" } : { x: o.left, y: H - o.bottom - r, turn: 270, c: "bl" })
        fillets.push(top ? { x: W - o.right - r, y: o.top, turn: 90, c: "tr" } : { x: W - o.right - r, y: H - o.bottom - r, turn: 180, c: "br" })
    }
    if (ow > 0) {
        // The straight rule along this band's inner edge (a docked bar rules its own edge).
        if (bw > 0) {
            var x0 = o.left + r - (r === 0 ? ow : 0), x1 = W - o.right - r + (r === 0 ? ow : 0)
            rules.push({ x: x0, y: top ? edgeY - ow : edgeY, w: x1 - x0, h: ow, band: true })
        } else if (r === 0) {
            // A docked bar and square corners: the corner's pixel joins the bar's rule to the side's.
            rules.push({ x: o.left - ow, y: top ? edgeY - ow : edgeY, w: ow, h: ow, c: top ? "tl" : "bl" })
            rules.push({ x: W - o.right, y: top ? edgeY - ow : edgeY, w: ow, h: ow, c: top ? "tr" : "br" })
        }
        // Round each fillet: centred on the arc's centre, the line inside the band.
        if (r > 0) {
            var rho = r + ow / 2, cyA = top ? o.top + r : H - o.bottom - r
            var lx = o.left + r, rx = W - o.right - r
            arcs.push({ c: top ? "tl" : "bl", p: top ? arc(lx, cyA, rho, -Math.PI / 2, -Math.PI) : arc(lx, cyA, rho, Math.PI, Math.PI / 2) })
            arcs.push({ c: top ? "tr" : "br", p: top ? arc(rx, cyA, rho, -Math.PI / 2, 0) : arc(rx, cyA, rho, 0, Math.PI / 2) })
        }
    }
    return { y0: y0, d: d, fills: fills, fillets: fillets, rules: rules, arcs: arcs }
}

// A side strip's pieces (`left` true for the left one): its band, wide as the band, between the fillets' ends.
function side(g, left) {
    var W = g.sw, H = g.sh, o = g.o, b = g.b, r = g.r, ow = g.ow
    var e = left ? "left" : "right", bw = b[e]
    var y0 = Math.max(o.top + r, sideFrom(g, e)), y1 = H - Math.max(o.bottom + r, sideTo(g, e))
    var x = left ? 0 : W - Math.max(1, bw)
    var fills = [], rules = []
    if (bw > 0 && y1 > y0) {
        fills.push({ x: left ? 0 : W - bw, y: y0, w: bw, h: y1 - y0 })
        if (ow > 0) rules.push({ x: left ? bw - ow : W - bw, y: y0, w: ow, h: y1 - y0 })
    }
    return { x: x, y0: y0, y1: y1, w: Math.max(1, bw), fills: fills, rules: rules }
}
