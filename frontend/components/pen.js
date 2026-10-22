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
// from the top-left corner's end). The corner radius stays at least 1.5 px: a pen does not turn on a point.
function roundRect(w, h, r, inset) {
    var x0 = inset, y0 = inset, x1 = w - inset, y1 = h - inset
    var rc = clamp(r - inset, 1.5, Math.max(1.5, Math.min((x1 - x0) / 2, (y1 - y0) / 2)))
    var pts = []
    function arc(cx, cy, a0) {
        var n = Math.max(4, Math.ceil(rc * Math.PI / 2))
        for (var k = 0; k <= n; k++) {
            var a = a0 + (Math.PI / 2) * k / n
            pts.push({ x: cx + rc * Math.cos(a), y: cy + rc * Math.sin(a) })
        }
    }
    arc(x1 - rc, y0 + rc, -Math.PI / 2)
    arc(x1 - rc, y1 - rc, 0)
    arc(x0 + rc, y1 - rc, Math.PI / 2)
    arc(x0 + rc, y0 + rc, Math.PI)
    return pts
}

// A closed polyline resampled every ~`step` px of arc length: {pts: [{x, y, tx, ty}], L, step}.
function resample(src, step) {
    var n = src.length, cum = [0], L = 0
    for (var i = 0; i < n; i++) {
        var a = src[i], b = src[(i + 1) % n]
        L += Math.hypot(b.x - a.x, b.y - a.y)
        cum.push(L)
    }
    var N = Math.max(8, Math.round(L / step))
    var du = L / N, pts = [], j = 0
    for (var k = 0; k < N; k++) {
        var s = k * du
        while (j < n - 1 && cum[j + 1] < s) j++
        var p = src[j], q = src[(j + 1) % n]
        var seg = cum[j + 1] - cum[j]
        var t = seg > 0 ? (s - cum[j]) / seg : 0
        pts.push({ x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t })
    }
    for (var m = 0; m < N; m++) {
        var pa = pts[(m + N - 1) % N], pb = pts[(m + 1) % N]
        var dx = pb.x - pa.x, dy = pb.y - pa.y, l = Math.hypot(dx, dy) || 1
        pts[m].tx = dx / l
        pts[m].ty = dy / l
    }
    return { pts: pts, L: L, step: du }
}

// The point at arc length s (any s: it wraps round the loop), interpolated between samples.
function at(loop, s) {
    var N = loop.pts.length
    var u = ((s % loop.L) + loop.L) % loop.L / loop.step
    var i = Math.floor(u), t = u - i
    var a = loop.pts[i % N], b = loop.pts[(i + 1) % N]
    var tx = a.tx + (b.tx - a.tx) * t, ty = a.ty + (b.ty - a.ty) * t
    var l = Math.hypot(tx, ty) || 1
    return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, tx: tx / l, ty: ty / l }
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

// Draws one outline. o: {pts (closed polyline, canvas coordinates), width, color, line, pressure, breaks, fade, wobble,
// seed, W, H (the canvas, for the fade)}. The caller clears the canvas; the colour's alpha is the canvas's opacity.
function outline(ctx, o) {
    var loop = resample(o.pts, 1.5)
    var L = loop.L
    if (L < 8) return
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
        var N = Math.max(6, Math.round(L / S)), unit = L / N, ph = R() * unit
        for (var i = 0; i < N; i++) {
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
        var Nd = Math.max(4, Math.round(L / (Ld + Gd))), ud = L / Nd
        var dash = Math.max(1, ud * Ld / (Ld + Gd) - w), phd = R() * ud
        for (var j = 0; j < Nd; j++) {
            var a = phd + j * ud
            run(ctx, loop, F, w, a, a + dash, function (s) { return 1 })
        }
    } else if (line === "broken") {
        // Long strokes, each its own: the pen lifted and came down a little off the last one.
        var s0 = R() * L, pos = s0, end = s0 + L
        var scale = clamp(L / 360, 0.35, 1)
        while (pos < end - 6) {
            var len = (45 + 95 * R()) * scale + 10
            var gap = 3.5 + 6 * R() + w
            var b = Math.min(pos + len, end - gap)
            if (b - pos < 6) break
            var d0 = (R() - 0.5) * 0.9, d1 = (R() - 0.5) * 0.9
            ;(function (sa, sb, da, db) {
                run(ctx, loop, F, w, sa, sb,
                    function (s) {
                        // A landing blob, a lift that thins out.
                        return (1 + 0.22 * (1 - smooth(0, 2.5, s - sa))) * (0.5 + 0.5 * smooth(0, 6, sb - s))
                    },
                    function (s) { return da + (db - da) * (s - sa) / (sb - sa) })
            })(pos, b, d0, d1)
            pos = b + gap
        }
    } else if (line === "rough") {
        // A very uneven hand: a strong wander, a loop that closes past its start a little off, a second faint pass.
        var RA = 1.6 * clamp(L / 600, 0.5, 1)
        var rn = loopNoise(R, L, 70), rj = loopNoise(R, L, 13), rn2 = loopNoise(R, L, 60)
        var over = clamp(L * 0.03, 6, 16)
        var sr = R() * L, sr2 = R() * L, side = R() < 0.5 ? -1 : 1, in2 = (R() < 0.5 ? -1 : 1) * 0.9
        faint(ctx, loop, F, Math.max(0.5, 0.7 * w), sr2, sr2 + L * 0.96,
              function (s) { return RA * rn2(s) + in2 }, 0.42)
        run(ctx, loop, F, w * 1.1, sr, sr + L + over,
            function (s) { return 0.75 + 0.25 * smooth(0, 5, sr + L + over - s) },
            function (s) { return RA * (0.8 * rn(s) + 0.2 * rj(s)) + side * 1.4 * (s - sr) / (L + over) })
    } else {
        run(ctx, loop, F, w, 0, L)
    }
    fade(ctx, o.W, o.H, o.fade || 0, o.seed)
}
