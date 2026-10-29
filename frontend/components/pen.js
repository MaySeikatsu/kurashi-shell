.pragma library
// The pen (K62, docs/ux/texture.md "The pen"): how an outline is drawn on a Canvas 2D context — a line style
// (solid | dotted | dashed | broken | rough) and four modifiers, each 0..1 and separate: pressure (the width swells and
// thins 0.6×–1.6× at 1, after a nib held at an angle and a slow change of pressure), breaks (small skips where the pen
// lifted, the line thinning into them), fade (the ink's flow: opacity varies, never below 55 %), wobble (a hand that
// wanders: lines and curves bow and drift, at most ~1.5 px on a long line). Everything is seeded (callers seed by size:
// the same size draws the same line, so nothing shimmers) and drawn once; the caller repaints only when an input changes.
//
// Ink is laid opaque — overlapping round caps of opaque segments cannot bead — and the ink's alpha comes afterwards:
// `fade` multiplies a smooth field over the canvas (`destination-in`), the colour's alpha is the canvas item's opacity.
// A path is a closed polyline resampled by arc length; the noise is periodic over its length, so the loop has no seam.

var NIB = 35 * Math.PI / 180

// A seeded generator (mulberry32): the same numbers for the same seed.
function rng(seed) {
    var s = seed >>> 0
    return function () {
        s = (s + 0x6D2B79F5) >>> 0
        var t = s
        t = Math.imul(t ^ (t >>> 15), t | 1)
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}

function seedOf(w, h, salt) {
    return ((Math.round(w) * 73856093) ^ (Math.round(h) * 19349663) ^ (salt | 0)) >>> 0
}

// The per-block salt, so equal-sized blocks (a grid of quick tiles) do not draw identical lines: the item's place in its
// parent and its parent's place in the grandparent, on a 24 px grid. It is read when a line is painted (a size, colour
// or token change, or when the block lands in another 24 px cell of its parent — layout settling after the first paint),
// so a block that does not move never changes its line. Ancestors' own motion (a card sliding in) does not enter it. A caller with a better identity passes an explicit seed.
function cell(v) { return Math.floor((v + 12) / 24) }

function salt(item) {
    var h = 0x811C9DC5
    for (var it = item, k = 0; it && k < 2; it = it.parent, k++) {
        h = Math.imul(h ^ cell(it.x), 16777619) >>> 0
        h = Math.imul(h ^ cell(it.y), 16777619) >>> 0
    }
    return h
}

function clamp(x, a, b) { return Math.max(a, Math.min(b, x)) }
function smooth(e0, e1, x) { var t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t) }

// A smooth seeded noise over a loop `L` px long, about −1..1: three sines with whole numbers of cycles round the loop,
// near `lambda` px apart, so the value where the line closes equals the value where it began.
function loopNoise(R, L, lambda) {
    var spec = [[1, 1], [0.5, 0.45], [2.4, 0.7]]
    var parts = [], sum = 0
    for (var i = 0; i < spec.length; i++) {
        parts.push({ k: Math.max(1, Math.round(L / (lambda * spec[i][0]))), a: spec[i][1], ph: R() * Math.PI * 2 })
        sum += spec[i][1]
    }
    var norm = 1.5 / sum
    return function (s) {
        var v = 0
        for (var j = 0; j < parts.length; j++) v += parts[j].a * Math.sin(2 * Math.PI * parts[j].k * s / L + parts[j].ph)
        return clamp(v * norm, -1, 1)
    }
}

// The closed outline of a w × h rounded rectangle whose line runs `inset` px inside the edge, as points (clockwise
// from the top-left corner's end). `r` is one radius, or [top-left, top-right, bottom-right, bottom-left]. A corner
// keeps at least 1.5 px: a pen does not turn on a point. `sq`: squircle corners (corner.js's cubic, I281).
function roundRect(w, h, r, inset, sq) {
    var x0 = inset, y0 = inset, x1 = w - inset, y1 = h - inset
    var rs = typeof r === "number" ? [r, r, r, r] : r
    var lim = Math.max(1.5, Math.min((x1 - x0) / 2, (y1 - y0) / 2))
    var pts = []
    function arc(rr, cx, cy, a0) {
        var rc = clamp(rr - inset, 1.5, lim)
        cx += cx < w / 2 ? rc : -rc
        cy += cy < h / 2 ? rc : -rc
        var n = Math.max(4, Math.ceil(rc * Math.PI / 2))
        if (sq && rc < lim - 0.5) {
            // The squircle's cubic (a pill's round end stays round) between the arc's ends, its handles `sq` of the way to the
            // corner point (Theme.squircle, I300; 0.88 for a plain `true`).
            var a1 = a0 + Math.PI / 2, kq = typeof sq === "number" && sq > 0.56 && sq < 1 ? sq : 0.88
            var sx = cx + rc * Math.cos(a0), sy = cy + rc * Math.sin(a0), ex = cx + rc * Math.cos(a1), ey = cy + rc * Math.sin(a1)
            var qx = cx + rc * (Math.cos(a0) + Math.cos(a1)), qy = cy + rc * (Math.sin(a0) + Math.sin(a1))
            var hx = sx + (qx - sx) * kq, hy = sy + (qy - sy) * kq, gx = ex + (qx - ex) * kq, gy = ey + (qy - ey) * kq
            for (var j = 0; j <= n; j++) {
                var t = j / n, u = 1 - t
                pts.push({ x: u * u * u * sx + 3 * u * u * t * hx + 3 * u * t * t * gx + t * t * t * ex,
                           y: u * u * u * sy + 3 * u * u * t * hy + 3 * u * t * t * gy + t * t * t * ey })
            }
            return
        }
        for (var k = 0; k <= n; k++) {
            var a = a0 + (Math.PI / 2) * k / n
            pts.push({ x: cx + rc * Math.cos(a), y: cy + rc * Math.sin(a) })
        }
    }
    arc(rs[1], x1, y0, -Math.PI / 2)
    arc(rs[2], x1, y1, 0)
    arc(rs[3], x0, y1, Math.PI / 2)
    arc(rs[0], x0, y0, Math.PI)
    return pts
}

// An SVG path of absolute M, L, A (circular, small arc), C (a squircle corner) and Z commands — the paths MorphShape builds — as polylines:
// [{pts, closed}], one per subpath. Arcs are sampled every ~1.5 px.
function svgPaths(d) {
    var tok = (d || "").trim().split(/[\s,]+/)
    var out = [], cur = null, i = 0, px = 0, py = 0
    function num() { return parseFloat(tok[i++]) }
    while (i < tok.length) {
        var c = tok[i++]
        if (c === "M") {
            px = num(); py = num()
            cur = { pts: [{ x: px, y: py }], closed: false }
            out.push(cur)
        } else if (c === "L") {
            px = num(); py = num()
            if (cur) cur.pts.push({ x: px, y: py })
        } else if (c === "A") {
            var r = num(); num(); num(); num()
            var sweep = num(), x = num(), y = num()
            var dx = x - px, dy = y - py, q = Math.hypot(dx, dy)
            if (cur && q > 1e-6) {
                r = Math.max(r, q / 2)
                var hh = Math.sqrt(Math.max(0, r * r - q * q / 4))
                // The centre: on the chord's normal, to the side the sweep turns to (y down: sweep 1 = clockwise).
                var sgn = sweep === 1 ? 1 : -1
                var cx = (px + x) / 2 - sgn * hh * dy / q, cy = (py + y) / 2 + sgn * hh * dx / q
                var a0 = Math.atan2(py - cy, px - cx), a1 = Math.atan2(y - cy, x - cx)
                var da = a1 - a0
                if (sweep === 1 && da < 0) da += 2 * Math.PI
                if (sweep === 0 && da > 0) da -= 2 * Math.PI
                var n = Math.max(2, Math.ceil(Math.abs(da) * r / 1.5))
                for (var k = 1; k <= n; k++) {
                    var a = a0 + da * k / n
                    cur.pts.push({ x: cx + r * Math.cos(a), y: cy + r * Math.sin(a) })
                }
            }
            px = x; py = y
        } else if (c === "C") {
            // A cubic (a squircle corner, corner.js): sampled every ~1.5 px of its control polygon.
            var ax = num(), ay = num(), bx = num(), by = num(), ex = num(), ey = num()
            if (cur) {
                var len = Math.hypot(ax - px, ay - py) + Math.hypot(bx - ax, by - ay) + Math.hypot(ex - bx, ey - by)
                var m = Math.max(2, Math.ceil(len / 1.5))
                for (var j = 1; j <= m; j++) {
                    var t = j / m, u = 1 - t
                    cur.pts.push({ x: u * u * u * px + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * ex,
                                   y: u * u * u * py + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * ey })
                }
            }
            px = ex; py = ey
        } else if (c === "Z") {
            if (cur) cur.closed = true
        }
    }
    return out
}

// A polyline resampled every ~`step` px of arc length: {pts: [{x, y, tx, ty}], L, step, closed}. A closed one joins
// its last point to its first.
function resample(src, step, closed) {
    if (closed === undefined) closed = true
    var n = src.length, cum = [0], L = 0
    var segs = closed ? n : n - 1
    for (var i = 0; i < segs; i++) {
        var a = src[i], b = src[(i + 1) % n]
        L += Math.hypot(b.x - a.x, b.y - a.y)
        cum.push(L)
    }
    var N = Math.max(closed ? 8 : 1, Math.round(L / step))
    var du = L / N, pts = [], j = 0
    var count = closed ? N : N + 1
    for (var k = 0; k < count; k++) {
        var s = k * du
        while (j < segs - 1 && cum[j + 1] < s) j++
        var p = src[j], q = src[(j + 1) % n]
        var seg = cum[j + 1] - cum[j]
        var t = seg > 0 ? Math.min(1, (s - cum[j]) / seg) : 0
        pts.push({ x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t })
    }
    for (var m = 0; m < count; m++) {
        var pa = closed ? pts[(m + count - 1) % count] : pts[Math.max(0, m - 1)]
        var pb = closed ? pts[(m + 1) % count] : pts[Math.min(count - 1, m + 1)]
        var dx = pb.x - pa.x, dy = pb.y - pa.y, l = Math.hypot(dx, dy) || 1
        pts[m].tx = dx / l
        pts[m].ty = dy / l
    }
    return { pts: pts, L: L, step: du, closed: closed }
}

// The point at arc length s, interpolated between samples: round the loop for a closed line, straight on past the
// ends (along the end's direction) for an open one.
function at(loop, s) {
    var N = loop.pts.length
    if (!loop.closed) {
        var e = s < 0 ? loop.pts[0] : (s > loop.L ? loop.pts[N - 1] : null)
        if (e) {
            var o = s < 0 ? s : s - loop.L
            return { x: e.x + e.tx * o, y: e.y + e.ty * o, tx: e.tx, ty: e.ty }
        }
    }
    var u = loop.closed ? ((s % loop.L) + loop.L) % loop.L / loop.step : s / loop.step
    var i = Math.floor(u), t = u - i
    if (!loop.closed && i >= N - 1) { i = N - 2; t = 1 }
    var a = loop.pts[((i % N) + N) % N], b = loop.pts[(i + 1) % N]
    var tx = a.tx + (b.tx - a.tx) * t, ty = a.ty + (b.ty - a.ty) * t
    var l = Math.hypot(tx, ty) || 1
    return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, tx: tx / l, ty: ty / l }
}

// A seed from a name (FNV-1a): a surface that knows who it is ("stage-card") seeds its line with it.
function hashStr(str) {
    var h = 0x811C9DC5
    for (var i = 0; i < str.length; i++) h = Math.imul(h ^ str.charCodeAt(i), 16777619) >>> 0
    return h & 0x7FFFFFFF
}

// The modifiers along a line `L` px long: off(s) the wobble (px along the normal), mult(s, θ) the pressure's width
// factor, ink(s) 0 inside a skip and a taper factor < 1 just before and after one (the pen lifting and landing).
function field(L, width, mods, seed) {
    var R = rng(seed ^ 0x2545F491)
    var bow = loopNoise(R, L, clamp(L / 5, 50, 160))
    var fine = loopNoise(R, L, 26)
    var pn = loopNoise(R, L, 46)
    var A = (mods.wobble || 0) * 1.5 * clamp(L / 900, 0.35, 1)
    var P = mods.pressure || 0
    var gaps = []
    if ((mods.breaks || 0) > 0) {
        var D = 420 - 340 * mods.breaks
        var s = R() * D * 0.7 + 6
        while (s < L - 8) {
            var g = 1.6 + 2.4 * R() + width
            gaps.push([s, s + g])
            s += g + D * (0.45 + 1.1 * R())
        }
    }
    function gapDist(s) {
        var best = 1e9
        for (var i = 0; i < gaps.length; i++) {
            var a = gaps[i][0], b = gaps[i][1]
            for (var w = -1; w <= 1; w++) {
                var x = s + w * L
                if (x >= a && x <= b) return -1
                best = Math.min(best, Math.abs(x - a), Math.abs(x - b))
            }
        }
        return best
    }
    return {
        off: function (s) { return A === 0 ? 0 : A * (0.72 * bow(s) + 0.28 * fine(s)) },
        mult: function (s, th) {
            if (P <= 0) return 1
            var dir = Math.abs(Math.sin(th + NIB))
            var m = 0.6 + clamp(0.45 * dir + 0.55 * (0.5 + 0.5 * pn(s)), 0, 1)
            return 1 + P * (m - 1)
        },
        ink: function (s) {
            if (gaps.length === 0) return 1
            var d = gapDist(s)
            return d < 0 ? 0 : 0.45 + 0.55 * smooth(0, 4, d)
        }
    }
}

function rgb(c) { return "rgb(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ")" }

// One stroke from arc length sa to sb (sb may pass L: it wraps): opaque round-capped segments, the width
// `w × pressure × wf(s)` and the offset `field.off(s) + df(s)` along the normal. Skips leave gaps.
function run(ctx, loop, F, w, sa, sb, wf, df) {
    var step = loop.step
    var ss = [sa]
    for (var k = Math.ceil(sa / step + 1e-6); k * step < sb; k++) ss.push(k * step)
    ss.push(sb)
    var prev = null
    for (var i = 0; i < ss.length; i++) {
        var s = ss[i], p = at(loop, s)
        var ink = F.ink(s)
        if (ink <= 0) { prev = null; continue }
        var o = F.off(s) + (df ? df(s) : 0)
        var cur = {
            x: p.x - p.ty * o, y: p.y + p.tx * o,
            w: Math.max(0.45, w * F.mult(s, Math.atan2(p.ty, p.tx)) * ink * (wf ? wf(s) : 1))
        }
        if (prev) {
            ctx.beginPath()
            ctx.moveTo(prev.x, prev.y)
            ctx.lineTo(cur.x, cur.y)
            ctx.lineWidth = (prev.w + cur.w) / 2
            ctx.stroke()
        } else if (i === ss.length - 1 || F.ink(ss[i + 1]) <= 0) {
            ctx.beginPath()
            ctx.arc(cur.x, cur.y, cur.w / 2, 0, 2 * Math.PI)
            ctx.fill()
        }
        prev = cur
    }
}

// A faint pass at one width (rough's second line): one path, so it is one shape at `alpha` with no beads.
function faint(ctx, loop, F, w, sa, sb, df, alpha) {
    var step = loop.step
    ctx.save()
    ctx.globalAlpha = alpha
    ctx.lineWidth = w
    ctx.beginPath()
    var open = false
    for (var s = sa; s <= sb; s += step) {
        if (F.ink(s) <= 0) { open = false; continue }
        var p = at(loop, s), o = F.off(s) + df(s)
        var x = p.x - p.ty * o, y = p.y + p.tx * o
        if (open) ctx.lineTo(x, y)
        else { ctx.moveTo(x, y); open = true }
    }
    ctx.stroke()
    ctx.restore()
}

// The ink's flow: two smooth fields across the canvas, one along each diagonal (so opposite sides of a box never fade
// alike), multiply the alpha of what is drawn; each stays ≥ √0.55, so the product never drops below 55 %.
function fade(ctx, W, H, amount, seed) {
    if (amount <= 0) return
    var R = rng(seed ^ 0x51ED27)
    var lo = 1 - amount * (1 - Math.sqrt(0.55))
    var dirs = [[0, 0, W, H], [W, 0, 0, H]]
    ctx.save()
    ctx.globalCompositeOperation = "destination-in"
    for (var d = 0; d < dirs.length; d++) {
        var len = Math.hypot(W, H)
        var n = Math.max(2, Math.round(len / 30))
        var g = ctx.createLinearGradient(dirs[d][0], dirs[d][1], dirs[d][2], dirs[d][3])
        var v = R()
        for (var i = 0; i <= n; i++) {
            // A gentle walk, not white noise: the flow changes over a stroke, not every few pixels.
            v = clamp(v + (R() - 0.5) * 1.1, 0, 1)
            g.addColorStop(i / n, "rgba(0,0,0," + (lo + (1 - lo) * v).toFixed(3) + ")")
        }
        ctx.fillStyle = g
        ctx.fillRect(0, 0, W, H)
    }
    ctx.restore()
}

// Draws one outline and its ink's flow. As `stroke`, plus W, H (the canvas, for the fade). The caller clears the
// canvas; the colour's alpha is the canvas's opacity.
function outline(ctx, o) {
    stroke(ctx, o)
    fade(ctx, o.W, o.H, o.fade || 0, o.seed)
}

// Draws one line, no fade. o: {pts (polyline, canvas coordinates), closed (default true), width, color, line, pressure,
// breaks, wobble, seed}. A closed line starts anywhere round its loop (seeded); an open one (a bar's rule, a card hung
// from it) starts at its first point, and its dots and dashes end level at both ends.
function stroke(ctx, o) {
    var closed = o.closed === undefined ? true : o.closed
    var loop = resample(o.pts, 1.5, closed)
    var L = loop.L
    if (L < (closed ? 8 : 2)) return
    var w = o.width
    var F = field(L, w, o, o.seed)
    var R = rng(o.seed ^ 0x7F4A7C15)
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    ctx.strokeStyle = rgb(o.color)
    ctx.fillStyle = rgb(o.color)
    var line = o.line || "solid"
    if (line === "dotted") {
        var r0 = Math.max(1, 0.8 * w)
        var S = 2 * r0 + Math.max(2.2, 2.6 * r0)
        var N = Math.max(closed ? 6 : 1, Math.round(L / S)), unit = L / N, ph = closed ? R() * unit : 0
        for (var i = 0; i < N + (closed ? 0 : 1); i++) {
            var s = ph + i * unit
            var ink = F.ink(s)
            if (ink <= 0) continue
            var p = at(loop, s), off = F.off(s)
            var rr = Math.max(0.5, r0 * F.mult(s, Math.atan2(p.ty, p.tx)) * (0.6 + 0.4 * ink))
            ctx.beginPath()
            ctx.arc(p.x - p.ty * off, p.y + p.tx * off, rr, 0, 2 * Math.PI)
            ctx.fill()
        }
    } else if (line === "dashed") {
        var Ld = Math.max(5, 4 * w + 3), Gd = Math.max(3.5, 2.2 * w + 2.2)
        var Nd = Math.max(closed ? 4 : 1, Math.round(L / (Ld + Gd))), ud = L / Nd
        var dash = Math.max(1, ud * Ld / (Ld + Gd) - w), phd = closed ? R() * ud : (ud - dash) / 2
        for (var j = 0; j < Nd; j++) {
            var a = phd + j * ud
            run(ctx, loop, F, w, a, a + dash, function (s) { return 1 })
        }
    } else if (line === "broken") {
        // Long strokes, each its own: the pen lifted and came down a little off the last one.
        var s0 = closed ? R() * L : 0, pos = s0, end = s0 + L
        var scale = clamp(L / 360, 0.35, 1)
        while (pos < end - (closed ? 6 : 0.5)) {
            var len = (45 + 95 * R()) * scale + 10
            var gap = 3.5 + 6 * R() + w
            var b = closed ? Math.min(pos + len, end - gap) : Math.min(pos + len, end)
            if (b - pos < (closed ? 6 : 0.5)) break
            var d0 = (R() - 0.5) * 0.9, d1 = (R() - 0.5) * 0.9
            ;(function (sa, sb, da, db) {
                run(ctx, loop, F, w, sa, sb,
                    function (s) {
                        // A landing blob, a lift that thins out.
                        return (1 + 0.22 * (1 - smooth(0, 2.5, s - sa))) * (0.5 + 0.5 * smooth(0, 6, sb - s))
                    },
                    function (s) { return da + (db - da) * (s - sa) / Math.max(1, sb - sa) })
            })(pos, b, d0, d1)
            pos = b + gap
        }
    } else if (line === "rough") {
        // A very uneven hand: a strong wander, a loop that closes past its start a little off (an open line runs a
        // little past its ends), a second faint pass.
        var RA = 1.6 * clamp(L / 600, 0.5, 1)
        var rn = loopNoise(R, L, 70), rj = loopNoise(R, L, 13), rn2 = loopNoise(R, L, 60)
        var over = closed ? clamp(L * 0.03, 6, 16) : clamp(L * 0.03, 2, 6)
        var sr = closed ? R() * L : -over / 2, sr2 = closed ? R() * L : 0
        var side = R() < 0.5 ? -1 : 1, in2 = (R() < 0.5 ? -1 : 1) * 0.9
        faint(ctx, loop, F, Math.max(0.5, 0.7 * w), sr2, sr2 + L * (closed ? 0.96 : 1),
              function (s) { return RA * rn2(s) + in2 }, 0.42)
        run(ctx, loop, F, w * 1.1, sr, sr + L + over,
            function (s) { return 0.75 + 0.25 * smooth(0, 5, sr + L + over - s) },
            function (s) { return RA * (0.8 * rn(s) + 0.2 * rj(s)) + (closed ? side * 1.4 * (s - sr) / (L + over) : 0) })
    } else if (line === "sketch") {
        // Kami's hand (frames/Sketch.qml) for any line (the frame outline's `sketch` stroke): two passes, the second a
        // little off the first and thinner, each drifting slowly (under a pixel, a hand, not a jitter) with the pressure
        // swelling and thinning; past the ends a little, where the pen came back round.
        var dn = loopNoise(R, L, 40), dn2 = loopNoise(R, L, 34), pn = loopNoise(R, L, 55), pn2 = loopNoise(R, L, 47)
        var ovs = closed ? clamp(L * 0.02, 2, 5) : 2.5
        var sa1 = closed ? R() * L : -ovs, sa2 = closed ? R() * L : -ovs * 0.6
        run(ctx, loop, F, 0.8 * w, sa1, sa1 + L + (closed ? ovs : 2 * ovs),
            function (s) { return 0.85 + 0.3 * pn(s) }, function (s) { return 0.6 * dn(s) })
        run(ctx, loop, F, 0.62 * w, sa2, sa2 + L + (closed ? ovs * 0.6 : 1.2 * ovs),
            function (s) { return 0.8 + 0.25 * pn2(s) }, function (s) { return 0.7 + 0.6 * dn2(s) })
    } else {
        run(ctx, loop, F, w, 0, L)
    }
}
