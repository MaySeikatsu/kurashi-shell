.pragma library

// The curves of the motion engine (K83, docs/ux/motion-engine.md §4, §9): how time maps to progress. A curve comes as
// the daemon's token `motion.curve.<role>` (W59 contract) — {kind: "cubic", ms, points: [c1x c1y c2x c2y ex ey …]}
// (QML bezierCurve order, last point 1, 1) · {kind: "spring", ms, response, bounce} (SwiftUI's model, mass 1) ·
// {kind: "spring_q", spring, damping} (K42's integrator in QML SpringAnimation units: calm, lively) · {kind: "steps",
// ms, n} · {kind: "linear", ms} · {kind: "none"} — or as a bare bezierCurve list (today's `motion.timed.*_curve`).
// `prepare()` turns one into what the runners step (once per transition, cached by value); nothing here allocates
// per frame. Timed kinds (cubic, steps, linear) are evaluated by time fraction x ∈ [0, 1] (`at`, `slope`); springs are
// stepped by state (`springEval`, `springQStep`). No Qt, no tokens: Driver, MorphSprings and Settings' preview feed it.

var cache = new Map()
var CACHE_MAX = 64

function timedKind(k) { return k === "cubic" || k === "steps" || k === "linear" }

// A curve token (or a bezierCurve list) prepared: {kind, ms, …}. Unknown or missing → {kind: "none"}.
function prepare(c) {
    if (!c) return { kind: "none", ms: 0 }
    if (Array.isArray(c) || (typeof c === "object" && c.length !== undefined && c.kind === undefined))
        c = { kind: "cubic", ms: 0, points: c }
    var kind = c.kind
    var key
    if (kind === "cubic") key = "c" + (c.ms || 0) + ":" + Array.prototype.join.call(c.points || [], ",")
    else if (kind === "spring") key = "s" + (c.ms || 0) + ":" + (c.response || c.ms || 0) + ":" + (c.bounce || 0)
    else if (kind === "spring_q") key = "q" + c.spring + ":" + c.damping
    else if (kind === "steps") key = "t" + (c.ms || 0) + ":" + c.n
    else if (kind === "linear") key = "l" + (c.ms || 0)
    else return { kind: "none", ms: 0 }
    var hit = cache.get(key)
    if (hit) return hit
    var p
    if (kind === "cubic") p = prepareCubic(c.points || [], c.ms || 0)
    else if (kind === "spring") p = prepareSpring(c.response || c.ms || 0, c.bounce || 0, c.ms || 0)
    else if (kind === "spring_q") p = { kind: "spring_q", ms: 0, spring: Number(c.spring), damping: Number(c.damping) }
    else if (kind === "steps") p = { kind: "steps", ms: c.ms || 0, n: Math.max(1, Math.round(c.n || 1)) }
    else p = { kind: "linear", ms: c.ms || 0 }
    if (cache.size >= CACHE_MAX) cache.clear()
    cache.set(key, p)
    return p
}

// --- cubic segments ---------------------------------------------------------------------------------------------
// Each segment in polynomial form (x(t) = ((ax·t + bx)·t + cx)·t + x0, likewise y) with 11 samples of x(t) for Newton's
// first guess (WebKit's UnitBezier approach): 4 Newton steps, bisection where the slope is too flat to trust.
function prepareCubic(pts, ms) {
    var segs = []
    var x0 = 0, y0 = 0
    for (var i = 0; i + 5 < pts.length; i += 6) {
        var s = seg(x0, y0, pts[i], pts[i + 1], pts[i + 2], pts[i + 3], pts[i + 4], pts[i + 5])
        segs.push(s)
        x0 = pts[i + 4]; y0 = pts[i + 5]
    }
    if (segs.length === 0) segs.push(seg(0, 0, 0, 0, 1, 1, 1, 1))
    return { kind: "cubic", ms: ms, points: pts, segs: segs }
}

function seg(x0, y0, c1x, c1y, c2x, c2y, ex, ey) {
    var cx = 3 * (c1x - x0), bx = 3 * (c2x - c1x) - cx, ax = ex - x0 - cx - bx
    var cy = 3 * (c1y - y0), by = 3 * (c2y - c1y) - cy, ay = ey - y0 - cy - by
    var s = { x0: x0, y0: y0, ex: ex, ey: ey, ax: ax, bx: bx, cx: cx, ay: ay, by: by, cy: cy, c1x: c1x, c1y: c1y, samples: [] }
    for (var k = 0; k <= 10; k++) s.samples.push(sx(s, k / 10))
    return s
}
function sx(s, t) { return ((s.ax * t + s.bx) * t + s.cx) * t + s.x0 }
function sy(s, t) { return ((s.ay * t + s.by) * t + s.cy) * t + s.y0 }
function sdx(s, t) { return (3 * s.ax * t + 2 * s.bx) * t + s.cx }
function sdy(s, t) { return (3 * s.ay * t + 2 * s.by) * t + s.cy }

// The segment that holds time x (as ease.js picks it: the first whose end is at or past x, else the last).
function segOf(p, x) {
    var segs = p.segs
    for (var i = 0; i < segs.length - 1; i++) if (x <= segs[i].ex) return segs[i]
    return segs[segs.length - 1]
}

// The curve parameter t of segment s at time x.
function solve(s, x) {
    var smp = s.samples, t = 0
    // First guess: between the samples around x (x(t) is monotonic in every curve a token may carry).
    var k = 0
    while (k < 9 && smp[k + 1] < x) k++
    var span = smp[k + 1] - smp[k]
    t = (k + (span > 1e-12 ? (x - smp[k]) / span : 0)) / 10
    for (var n = 0; n < 4; n++) {
        var d = sdx(s, t)
        if (Math.abs(d) < 1e-6) break
        var e = sx(s, t) - x
        if (Math.abs(e) < 1e-9) return t
        t -= e / d
    }
    if (t >= 0 && t <= 1 && Math.abs(sx(s, t) - x) < 1e-7) return t
    // Bisection (ease.js's way): flat handles (a staircase's straight lines, decelerate's c1 = (0, 0)).
    var lo = 0, hi = 1
    t = 0.5
    for (var j = 0; j < 30; j++) {
        t = (lo + hi) / 2
        if (sx(s, t) < x) lo = t; else hi = t
    }
    return t
}

// --- evaluation by time fraction ---------------------------------------------------------------------------------
// y at time fraction x for the timed kinds (0 at x ≤ 0, exactly 1 at x ≥ 1, as ease.js); springs: their sampled step
// response (`springAtFraction`), for a scrubbed or plotted spring.
function at(p, x) {
    if (x <= 0) return 0
    if (x >= 1) return 1
    switch (p.kind) {
    case "cubic": var s = segOf(p, x); return sy(s, solve(s, x))
    // A staircase taken at the start of each step (today's `stepped_curve`: the jump, then the hold).
    case "steps": return Math.min(1, Math.ceil(x * p.n - 1e-9) / p.n)
    case "linear": return x
    case "spring": case "spring_q": return springAtFraction(p, x)
    }
    return 1
}

// dy/dx at time fraction x (the curve's slope; a velocity in travels per duration). Steps and the ends: 0.
function slope(p, x) {
    if (x <= 0 && p.kind === "cubic") {
        var f = p.segs[0]
        return f.c1x > 1e-6 ? (f.c1y - f.y0) / (f.c1x - f.x0) : 0
    }
    if (x <= 0 || x >= 1) return 0
    if (p.kind === "linear") return 1
    if (p.kind !== "cubic") return 0
    var s = segOf(p, x), t = solve(s, x), dx = sdx(s, t)
    if (Math.abs(dx) < 1e-6) return 0
    return Math.max(-50, Math.min(50, sdy(s, t) / dx))
}

// A cubic retargeted mid-flight (§7 interruptible): the first handle moved so the curve starts with `slope0` (dy/dx in
// travels per duration, from the velocity the value has), clamped to the token range (y ∈ [−1, 2]). A flat-started
// handle (c1x 0) gets a third of the first segment's width to carry the slope. Other kinds come back unchanged (springs
// keep their velocity natively; steps have none).
function retarget(p, slope0) {
    if (p.kind !== "cubic" || !isFinite(slope0)) return p
    var pts = p.points.slice()
    var ex = pts.length >= 6 ? pts[4] : 1
    var hx = pts[0] > 1e-3 ? pts[0] : ex / 3
    pts[0] = hx
    pts[1] = Math.max(-1, Math.min(2, slope0 * hx))
    return prepareCubic(pts, p.ms)
}

// --- springs (SwiftUI's model; brief §4) -------------------------------------------------------------------------
// response (ms) and bounce → ω₀ = 2π / response, damping 4π(1 − bounce) / response (bounce ≥ 0), 4π / (response(1 +
// bounce)) below; mass 1. `settle` is the time (ms) the step response takes to stay within 0.1 % of its target.
function prepareSpring(responseMs, bounce, ms) {
    var r = Math.max(0.05, responseMs / 1000)
    var w0 = 2 * Math.PI / r
    var c = bounce >= 0 ? 4 * Math.PI * (1 - bounce) / r : 4 * Math.PI / (r * (1 + bounce))
    var p = { kind: "spring", ms: ms || responseMs, response: responseMs, bounce: bounce, w0: w0, zeta: c / (2 * w0), settle: 0 }
    var o = { d: 0, v: 0 }
    var settle = 10000
    for (var t = 0; t <= 10000; t += 1000 / 120) {
        springEval(p, -1, 0, t, o)
        if (Math.abs(o.d) < 1e-3 && Math.abs(o.v) < 1e-2) {
            // (and stays: an underdamped spring crosses zero with speed, so velocity is part of the test)
            settle = t
            break
        }
    }
    p.settle = settle
    return p
}

// The displacement from the target `d` and velocity `v` (per second) `tMs` after a start at displacement d0 with
// velocity v0, into `out` ({d, v}: no allocation per frame).
function springEval(p, d0, v0, tMs, out) {
    var t = tMs / 1000, w0 = p.w0, z = p.zeta
    if (z < 1 - 1e-6) {
        var wd = w0 * Math.sqrt(1 - z * z)
        var a = d0, b = (v0 + z * w0 * d0) / wd
        var e = Math.exp(-z * w0 * t), co = Math.cos(wd * t), si = Math.sin(wd * t)
        out.d = e * (a * co + b * si)
        out.v = e * ((b * wd - z * w0 * a) * co - (a * wd + z * w0 * b) * si)
    } else if (z <= 1 + 1e-6) {
        var B = v0 + w0 * d0, ec = Math.exp(-w0 * t)
        out.d = ec * (d0 + B * t)
        out.v = ec * (B - w0 * (d0 + B * t))
    } else {
        var q = w0 * Math.sqrt(z * z - 1)
        var r1 = -z * w0 + q, r2 = -z * w0 - q
        var C2 = (v0 - r1 * d0) / (r2 - r1), C1 = d0 - C2
        var e1 = Math.exp(r1 * t), e2 = Math.exp(r2 * t)
        out.d = C1 * e1 + C2 * e2
        out.v = C1 * r1 * e1 + C2 * r2 * e2
    }
}

// K42's spring as QML's SpringAnimation integrates it, copied from MorphSprings (bit-exact): 16 ms steps of
// v += k·Δ − c·v, x += v·0.016, while `st.acc` (ms) holds a whole step. `st` = {x, v, acc}; returns nothing (in place).
function springQStep(st, to, k, c) {
    var x = st.x, v = st.v, acc = st.acc
    while (acc >= 16) {
        v = v + k * (to - x) - c * v; x += v * 0.016
        acc -= 16
    }
    st.x = x; st.v = v; st.acc = acc
}

// A spring's step response (0 → 1) at time fraction f of its settling: for scrubbing and plots. spring_q counts its
// 16 ms steps (with `k`, `c` when given: a Glide's own constants); the closed form samples at f · settle.
function springAtFraction(p, f, k, c) {
    if (f <= 0) return 0
    if (f >= 1) return 1
    if (p.kind === "spring") {
        var o = { d: 0, v: 0 }
        springEval(p, -1, 0, f * p.settle, o)
        return 1 + o.d
    }
    var kk = k === undefined || isNaN(k) ? p.spring : k
    var cc = c === undefined || isNaN(c) ? p.damping : c
    var n = springQSteps(kk, cc)
    var st = { x: 0, v: 0, acc: 16 * Math.round(f * n) }
    springQStep(st, 1, kk, cc)
    return st.x
}
// The 16 ms steps K42's spring takes from 0 to rest at 1 (within 0.1 %), at most 600 (9.6 s).
function springQSteps(k, c) {
    var st = { x: 0, v: 0, acc: 0 }
    for (var n = 1; n <= 600; n++) {
        st.acc = 16
        springQStep(st, 1, k, c)
        if (Math.abs(1 - st.x) < 1e-3 && Math.abs(st.v) < 1e-2) return n
    }
    return 600
}

// --- scrub (deterministic tests, docs/ux/motion-engine.md §9) ------------------------------------------------------
// KURASHI_MOTION_SCRUB=<p>: every Driver (and MorphSprings) holds its travel at p instead of moving. Parsed once per
// engine, logged once: `motion: scrub <p>`. −1 = off.
var scrubbed = null
function scrub(env) {
    if (scrubbed !== null) return scrubbed
    var v = env === undefined || env === null || env === "" ? NaN : Number(env)
    scrubbed = isFinite(v) ? Math.max(0, Math.min(1, v)) : -1
    if (scrubbed >= 0) console.log("motion: scrub " + scrubbed)
    return scrubbed
}
