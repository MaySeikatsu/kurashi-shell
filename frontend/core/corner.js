.pragma library

// One quarter corner, round or squircle (`theme.shape.corners`, token `shape.corner`; I281). A round corner is the
// quarter circle every shape drew; a squircle corner joins the same two points with one cubic whose handles reach
// further toward the corner — a superellipse-like curve (its middle about where a superellipse of exponent ~3.5 has it)
// with the same ends and the same tangents there, so lines, fillets and ruled joins meet it exactly as they met the arc.
// The theme scales the radius steps up for squircle looks (kurashi-theme `radius_steps`), so a squircle corner reads as
// round as the circle of the radius the user set.

// Handle length as a fraction of the way from an end to the corner point: 0.5523 draws a circle, more a squircle.
var K_CIRCLE = 0.5523
var K_SQUIRCLE = 0.88
// `sq` is the look's squircle ratio (`Theme.squircle`, token `shape.squircle_k`, I300) or `true` for the default one.
function kOf(sq) { return typeof sq === "number" && sq > K_CIRCLE && sq < 1 ? sq : K_SQUIRCLE }

function f(v) { return Math.round(v * 100) / 100 }

// The corner point of a quarter turn from (px, py) to (qx, qy) with axis-aligned tangents: of the two candidates
// (px, qy) and (qx, py) the one that is not the circle's centre. `sweep` as in SVG: 1 turns clockwise on screen
// (y down), so the centre lies to the right of the way from p to q.
function cornerOf(px, py, qx, qy, sweep) {
    var dx = qx - px, dy = qy - py
    var nx = sweep ? -dy : dy, ny = sweep ? dx : -dx
    // Candidate A = (px, qy): is it the centre?
    var aIsCentre = (0) * nx + (qy - py) * ny > 0
    return aIsCentre ? { x: qx, y: py } : { x: px, y: qy }
}

// SVG for a quarter turn of radius `r` from the current point (px, py) to (x, y): " A …" for a circle (exactly what
// the shapes drew before), " C …" for a squircle; a straight line below 0.05 px.
function quarter(px, py, r, sweep, x, y, sq) {
    if (!(r > 0.05)) return " L " + f(x) + " " + f(y)
    if (!sq) return " A " + f(r) + " " + f(r) + " 0 0 " + sweep + " " + f(x) + " " + f(y)
    var c = cornerOf(px, py, x, y, sweep), k = kOf(sq)
    return " C " + f(px + (c.x - px) * k) + " " + f(py + (c.y - py) * k)
        + " " + f(x + (c.x - x) * k) + " " + f(y + (c.y - y) * k) + " " + f(x) + " " + f(y)
}

// Points along a quarter turn from p to q round the corner point c (n + 1 points, both ends included): the circle's
// cubic or the squircle's.
function points(px, py, cx, cy, qx, qy, sq, n) {
    var k = sq ? kOf(sq) : K_CIRCLE
    var ax = px + (cx - px) * k, ay = py + (cy - py) * k, bx = qx + (cx - qx) * k, by = qy + (cy - qy) * k
    var out = []
    for (var i = 0; i <= n; i++) {
        var t = i / n, u = 1 - t
        out.push({ x: u * u * u * px + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * qx,
                   y: u * u * u * py + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * qy })
    }
    return out
}

// A rectangle (x, y, w, h) with corners tl, tr, br, bl (each clamped to half the shorter side), clockwise, as SVG.
function rect(x, y, w, h, tl, tr, br, bl, sq) {
    var m = Math.max(0, Math.min(w, h) / 2)
    tl = Math.min(Math.max(0, tl), m); tr = Math.min(Math.max(0, tr), m)
    br = Math.min(Math.max(0, br), m); bl = Math.min(Math.max(0, bl), m)
    var x1 = x + w, y1 = y + h
    return "M " + f(x + tl) + " " + f(y)
        + " L " + f(x1 - tr) + " " + f(y) + quarter(x1 - tr, y, tr, 1, x1, y + tr, sq)
        + " L " + f(x1) + " " + f(y1 - br) + quarter(x1, y1 - br, br, 1, x1 - br, y1, sq)
        + " L " + f(x + bl) + " " + f(y1) + quarter(x + bl, y1, bl, 1, x, y1 - bl, sq)
        + " L " + f(x) + " " + f(y + tl) + quarter(x, y + tl, tl, 1, x + tl, y, sq) + " Z"
}

// A path built with quarter arcs (`A r r 0 0 sweep x y`, absolute M/L/A/C/Z only, as every shape here writes them),
// with each quarter arc turned into the squircle corner — the shapes build their paths once and pass them through this
// (`sq` false: the path as it is). An arc that is not a quarter turn stays an arc, and so do two quarter arcs of one
// radius with (almost) no straight piece between them: a half circle, a pill's end, stays round (a capsule is a
// capsule in every look).
// `join` (session 28, I270; `theme.join_corner`, token `join.corner`): what stands in for a concave quarter arc — the
// fillet where two joined surfaces meet (a card and its bar, the dock, a sidebar and the frame) —: "chamfer" a straight
// cut, "steps" a pixel stair, "bulge" the quarter turned outward (a drop), "square" the bare corner; "round" (or none)
// leaves the fillet. Concave is told from the subpath's own direction: its corners turn the way it runs, a fillet the
// other way, so mirrored shapes need no flag.
function squircled(svg, sq, join) {
    if (join === "round" || join === undefined || join === "") join = null
    if ((!sq && !join) || !svg) return svg
    var t = svg.trim().split(/\s+/), segs = [], i = 0, cx = 0, cy = 0, sx = 0, sy = 0, cmd = ""
    while (i < t.length) {
        var tok = t[i]
        if (/^[MLACZ]$/.test(tok)) {
            cmd = tok
            i++
            if (cmd === "Z") { segs.push({ c: "Z", px: cx, py: cy, x: sx, y: sy }); cx = sx; cy = sy; continue }
        }
        if (cmd === "M" || cmd === "L") {
            var x = +t[i], y = +t[i + 1]
            segs.push({ c: cmd, a: [t[i], t[i + 1]], px: cx, py: cy, x: x, y: y })
            i += 2
            cx = x; cy = y
            if (cmd === "M") { sx = x; sy = y; cmd = "L" }
        } else if (cmd === "A") {
            var r = +t[i], ax = +t[i + 5], ay = +t[i + 6]
            segs.push({ c: "A", a: t.slice(i, i + 7), px: cx, py: cy, x: ax, y: ay, r: r,
                        q: Math.abs(Math.abs(ax - cx) - r) < 0.6 && Math.abs(Math.abs(ay - cy) - r) < 0.6 })
            i += 7
            cx = ax; cy = ay
        } else if (cmd === "C") {
            segs.push({ c: "C", a: t.slice(i, i + 6), px: cx, py: cy, x: +t[i + 4], y: +t[i + 5] })
            cx = +t[i + 4]; cy = +t[i + 5]
            i += 6
        } else {
            return svg   // a command this does not know: leave the path as it was built
        }
    }
    // The quarter arc of about this one's radius next to it across a line shorter than a quarter of that radius (a pill's
    // end, give or take an outline's width of straight side), in the direction `dir` (±1).
    function neighbour(k, dir) {
        var r = segs[k].r
        for (var j = k + dir; j >= 0 && j < segs.length; j += dir) {
            var g = segs[j]
            if (g.c === "L" && Math.hypot(g.x - g.px, g.y - g.py) < Math.max(0.5, r / 4)) continue
            return g.c === "A" && g.q ? g : null
        }
        return null
    }
    // Each subpath's direction (twice its signed area: > 0 runs clockwise on screen, y down), for telling fillets.
    if (join) {
        // (an open line — a pen's rule, a U round a card — is closed for the count by its last point's way back to its
        // first, or its direction would depend on where it lies in the window)
        var from = 0, area = 0, bx = 0, by = 0, lx = 0, ly = 0
        var close = function (end) {
            area += lx * by - bx * ly
            for (var n = from; n < end; n++) segs[n].cw = area > 0
            from = end; area = 0
        }
        for (var m = 0; m < segs.length; m++) {
            var e = segs[m]
            if (e.c === "M") { if (m > from) close(m); bx = e.x; by = e.y; lx = e.x; ly = e.y; continue }
            area += e.px * e.y - e.x * e.py
            lx = e.x; ly = e.y
        }
        close(segs.length)
    }
    var half = function (k) {
        var g = segs[k], nb = neighbour(k, -1), na = neighbour(k, 1)
        return (nb && Math.abs(nb.r - g.r) < 0.6) || (na && Math.abs(na.r - g.r) < 0.6)
    }
    var out = []
    for (var k = 0; k < segs.length; k++) {
        var g = segs[k]
        if (g.c === "Z") out.push("Z")
        else if (g.c !== "A") out.push(g.c, g.a.join(" "))
        else if (join && g.q && !half(k)) {
            // A quarter turn from p to q round the bare corner c: a fillet where two surfaces join, or a surface's own
            // corner (I489: the shape is for every corner of the sheet). A pill's end stays round.
            var c = cornerOf(g.px, g.py, g.x, g.y, +g.a[4])
            if (join === "chamfer") out.push("L", f(g.x) + " " + f(g.y))
            else if (join === "square") out.push("L", f(c.x) + " " + f(c.y), "L", f(g.x) + " " + f(g.y))
            else if (join === "steps") {
                var st = Math.max(2, Math.min(6, Math.round(g.r / 5)))
                var ux = (c.x - g.px) / st, uy = (c.y - g.py) / st, vx = (g.x - c.x) / st, vy = (g.y - c.y) / st
                for (var w = 1; w <= st; w++) {
                    out.push("L", f(g.px + ux * w + vx * (w - 1)) + " " + f(g.py + uy * w + vy * (w - 1)))
                    out.push("L", f(g.px + ux * w + vx * w) + " " + f(g.py + uy * w + vy * w))
                }
            } else if (join === "bulge") out.push(quarter(g.px, g.py, g.r, 1 - (+g.a[4]), g.x, g.y, sq).trim())
            else out.push("A", g.a.join(" "))
        } else if (!sq) out.push("A", g.a.join(" "))
        else {
            var nb = neighbour(k, -1), na = neighbour(k, 1)
            var halfCircle = (nb && Math.abs(nb.r - g.r) < 0.6) || (na && Math.abs(na.r - g.r) < 0.6)
            if (g.q && !halfCircle) out.push(quarter(g.px, g.py, g.r, +g.a[4], g.x, g.y, sq).trim())
            else out.push("A", g.a.join(" "))
        }
    }
    return out.join(" ")
}
