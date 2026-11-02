.pragma library
// The curve editor's arithmetic (W59.6; brief docs/ux/motion-engine.md §4). Two jobs, both Settings-only:
// 1. read a curve value the way kurashid does (`crates/kurashi-motion/src/curve.rs` `parse`, case for case), so a pasted
//    `easeOutBack` or Hyprland's `0.3, 0, 0.8, 0.15` is written back canonical (the daemon validates, it does not rewrite)
//    and the graph can draw what a row holds. The daemon stays the judge: a value this refuses is still sent as typed and
//    the daemon's reason is what the row shows.
// 2. sample curves for the graph and the spring plot (analytic spring of §4, mass 1).
// Stand-ins to replace (report W59.6): the preset table mirrors curve.rs PRESETS until the daemon publishes its curve list
// (CONTRACT-CHANGE row "motion curve presets"), and sampling should move to W59.2's frontend/core/motion/curves.js.

// --- limits (curve.rs) --------------------------------------------------------------------------------------------------
var X_MIN = 0, X_MAX = 1, Y_MIN = -1, Y_MAX = 2
var SPRING_MS_MIN = 50, SPRING_MS_MAX = 3000, BOUNCE_MIN = -0.5, BOUNCE_MAX = 0.9
var STEPS_MIN = 1, STEPS_MAX = 60

var EMPHASIZED = [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]

// id, usual ms, curve. Copied from curve.rs PRESETS (same order: the Presets tab lists them so).
var PRESETS = [
    { id: "expressive", ms: 500, curve: { kind: "cubic", points: [0.38, 1.21, 0.22, 1, 1, 1] } },
    { id: "emphasized", ms: 400, curve: { kind: "cubic", points: EMPHASIZED } },
    { id: "expressive-fast", ms: 350, curve: { kind: "cubic", points: [0.42, 1.67, 0.21, 0.9, 1, 1] } },
    { id: "effects", ms: 200, curve: { kind: "cubic", points: [0.34, 0.8, 0.34, 1, 1, 1] } },
    { id: "standard", ms: 300, curve: { kind: "cubic", points: [0.2, 0, 0, 1, 1, 1] } },
    { id: "emphasized-decelerate", ms: 400, curve: { kind: "cubic", points: [0.05, 0.7, 0.1, 1, 1, 1] } },
    { id: "emphasized-accelerate", ms: 200, curve: { kind: "cubic", points: [0.3, 0, 0.8, 0.15, 1, 1] } },
    { id: "decelerate", ms: 250, curve: { kind: "cubic", points: [0, 0, 0, 1, 1, 1] } },
    { id: "accelerate", ms: 200, curve: { kind: "cubic", points: [0.3, 0, 1, 1, 1, 1] } },
    { id: "fluent-exit", ms: 167, curve: { kind: "cubic", points: [1, 0, 1, 1, 1, 1] } },
    { id: "ease", ms: 250, curve: { kind: "cubic", points: [0.25, 0.1, 0.25, 1, 1, 1] } },
    { id: "ease-in", ms: 200, curve: { kind: "cubic", points: [0.42, 0, 1, 1, 1, 1] } },
    { id: "ease-out", ms: 250, curve: { kind: "cubic", points: [0, 0, 0.58, 1, 1, 1] } },
    { id: "ease-in-out", ms: 400, curve: { kind: "cubic", points: [0.42, 0, 0.58, 1, 1, 1] } },
    { id: "rubber", ms: 500, curve: { kind: "cubic", points: [0.34, 1.56, 0.64, 1, 1, 1] } },
    { id: "snap", ms: 450, curve: { kind: "cubic", points: [0.25, 0, 0.28, 0.838, 0.4, 0.88, 0.55, 0.9325, 0.75, 1, 1, 1] } },
    { id: "anticipate", ms: 500, curve: { kind: "cubic", points: [0.68, -0.55, 0.27, 1.55, 1, 1] } },
    { id: "drop", ms: 600, curve: { kind: "cubic", points: [
        0.25, 0, 0.45, 0.7, 0.55, 1,
        0.6, 0.96, 0.66, 0.94, 0.7, 0.94,
        0.74, 0.94, 0.8, 0.98, 0.85, 1,
        0.87, 0.99, 0.9, 0.985, 0.92, 0.985,
        0.95, 0.985, 0.98, 1, 1, 1] } },
    { id: "paper", ms: 520, curve: { kind: "cubic", points: [0.3, 0.7, 0.1, 1, 1, 1] } },
    { id: "calm", ms: 0, curve: { kind: "spring_q", spring: 4.0, damping: 0.45 } },
    { id: "lively", ms: 0, curve: { kind: "spring_q", spring: 3.2, damping: 0.26 } },
    { id: "gentle", ms: 450, curve: { kind: "spring", response: 450, bounce: 0 } },
    { id: "fluid", ms: 500, curve: { kind: "spring", response: 500, bounce: 0.25 } },
    { id: "bouncy", ms: 550, curve: { kind: "spring", response: 550, bounce: 0.45 } },
    { id: "pudding", ms: 650, curve: { kind: "spring", response: 650, bounce: 0.65 } },
    { id: "linear", ms: 250, curve: { kind: "linear" } }
]

var EASINGS_NET = {
    easeInSine: [0.12, 0, 0.39, 0], easeOutSine: [0.61, 1, 0.88, 1], easeInOutSine: [0.37, 0, 0.63, 1],
    easeInQuad: [0.11, 0, 0.5, 0], easeOutQuad: [0.5, 1, 0.89, 1], easeInOutQuad: [0.45, 0, 0.55, 1],
    easeInCubic: [0.32, 0, 0.67, 0], easeOutCubic: [0.33, 1, 0.68, 1], easeInOutCubic: [0.65, 0, 0.35, 1],
    easeInQuart: [0.5, 0, 0.75, 0], easeOutQuart: [0.25, 1, 0.5, 1], easeInOutQuart: [0.76, 0, 0.24, 1],
    easeInQuint: [0.64, 0, 0.78, 0], easeOutQuint: [0.22, 1, 0.36, 1], easeInOutQuint: [0.83, 0, 0.17, 1],
    easeInExpo: [0.7, 0, 0.84, 0], easeOutExpo: [0.16, 1, 0.3, 1], easeInOutExpo: [0.87, 0, 0.13, 1],
    easeInCirc: [0.55, 0, 1, 0.45], easeOutCirc: [0, 0.55, 0.45, 1], easeInOutCirc: [0.85, 0, 0.15, 1],
    easeInBack: [0.36, 0, 0.66, -0.56], easeOutBack: [0.34, 1.56, 0.64, 1], easeInOutBack: [0.68, -0.6, 0.32, 1.6]
}
var NOT_CUBIC = ["easeInElastic", "easeOutElastic", "easeInOutElastic", "easeInBounce", "easeOutBounce", "easeInOutBounce"]

function preset(id) {
    for (var i = 0; i < PRESETS.length; i++) if (PRESETS[i].id === id) return PRESETS[i]
    return null
}

// --- parse ---------------------------------------------------------------------------------------------------------------
// Result: {ok: true, type: "preset"|"curve"|"named", id?, curve?} or {ok: false, code: "error.config.curve.*"}.
function fail(code) { return { ok: false, code: "error.config.curve." + code } }

// Rust's f64::from_str: optional sign, digits with an optional point and exponent, or inf/infinity/nan.
var FLOAT = /^[+-]?(?:\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?|inf|infinity|nan)$/i
function rustFloat(t) {
    if (!FLOAT.test(t)) return NaN
    var l = t.toLowerCase().replace(/^[+-]/, "")
    if (l === "nan") return NaN
    if (l === "inf" || l === "infinity") return t[0] === "-" ? -Infinity : Infinity
    return parseFloat(t)
}
// Numbers separated by commas and/or whitespace; null when one is not a finite number.
function numbers(s) {
    var parts = s.split(/[,\s]/).filter(function (t) { return t !== "" })
    var out = []
    for (var i = 0; i < parts.length; i++) {
        var v = rustFloat(parts[i])
        if (!isFinite(v)) return null
        out.push(v)
    }
    return out
}
// `550`, `550ms` or `0.55s` -> ms; NaN when it is none of those.
function duration(s) {
    var t = s.trim(), v
    if (/ms$/.test(t)) v = rustFloat(t.slice(0, -2).trim())
    else if (/s$/.test(t)) v = rustFloat(t.slice(0, -1).trim()) * 1000
    else v = rustFloat(t)
    return isFinite(v) ? v : NaN
}
// A motion pack's curve name: lowercase ASCII, digits and dashes, starting with a letter, at most 48.
function isIdent(s) { return s.length <= 48 && /^[a-z][a-z0-9-]*$/.test(s) }

function validateCubic(n) {
    if (n.length === 0 || n.length % 6 !== 0) return "count"
    var inX = function (v) { return v >= X_MIN && v <= X_MAX }
    var inY = function (v) { return v >= Y_MIN && v <= Y_MAX }
    var x0 = 0
    for (var i = 0; i < n.length; i += 6) {
        var c1x = n[i], c1y = n[i + 1], c2x = n[i + 2], c2y = n[i + 3], ex = n[i + 4], ey = n[i + 5]
        if (!(inX(c1x) && inX(c2x) && inX(ex))) return "x_range"
        if (!(inY(c1y) && inY(c2y) && inY(ey))) return "y_range"
        if (ex < x0 || !(c1x >= x0 && c1x <= ex && c2x >= x0 && c2x <= ex)) return "order"
        x0 = ex
    }
    if (Math.abs(n[n.length - 2] - 1) > 1e-9 || Math.abs(n[n.length - 1] - 1) > 1e-9) return "end"
    return ""
}
function cubicOf(n) {
    var why = validateCubic(n)
    return why !== "" ? fail(why) : { ok: true, type: "curve", curve: { kind: "cubic", points: n } }
}

function parse(input) {
    var s = String(input === undefined || input === null ? "" : input).trim()
    if (s === "") return fail("syntax")
    var p = preset(s)
    if (p) return { ok: true, type: "preset", id: p.id, curve: p.curve, ms: p.ms }
    if (EASINGS_NET[s] !== undefined) { var e = EASINGS_NET[s]; return cubicOf([e[0], e[1], e[2], e[3], 1, 1]) }
    for (var i = 0; i < NOT_CUBIC.length; i++) if (s.indexOf(NOT_CUBIC[i]) === 0) return fail("not_cubic")
    var open = s.indexOf("(")
    if (open >= 0 && s[s.length - 1] === ")") {
        var name = s.slice(0, open).trim()
        var args = s.slice(open + 1, -1)
        var n
        switch (name) {
        case "cubic-bezier":
            n = numbers(args)
            if (n === null) return fail("syntax")
            if (n.length !== 4) return fail("count")
            return cubicOf([n[0], n[1], n[2], n[3], 1, 1])
        case "segments":
            n = numbers(args)
            if (n === null) return fail("syntax")
            return cubicOf(n)
        case "spring":
            var parts = args.split(",").map(function (t) { return t.trim() })
            if (parts.length !== 2) return fail("syntax")
            var ms = duration(parts[0])
            if (isNaN(ms)) return fail("syntax")
            if (!FLOAT.test(parts[1])) return fail("syntax")
            var bounce = rustFloat(parts[1])
            if (!(ms >= SPRING_MS_MIN && ms <= SPRING_MS_MAX) || !(bounce >= BOUNCE_MIN && bounce <= BOUNCE_MAX))
                return fail("spring_range")
            return { ok: true, type: "curve", curve: { kind: "spring", response: ms, bounce: bounce } }
        case "steps":
            var st = args.trim()
            if (!/^\+?\d+$/.test(st) || Number(st) > 4294967295) return fail("syntax")
            var k = Number(st)
            if (k < STEPS_MIN || k > STEPS_MAX) return fail("steps_range")
            return { ok: true, type: "curve", curve: { kind: "steps", n: k } }
        default:
            return fail("syntax")
        }
    }
    // Hyprland's `bezier = name, x0, y0, x1, y1` body, or four bare numbers from anywhere else.
    if (/^[0-9.\-]/.test(s)) {
        var bare = numbers(s)
        if (bare !== null) {
            if (bare.length !== 4) return fail("count")
            return cubicOf([bare[0], bare[1], bare[2], bare[3], 1, 1])
        }
    }
    if (isIdent(s)) return { ok: true, type: "named", id: s }
    return fail("syntax")
}

// --- canonical text -------------------------------------------------------------------------------------------------------
// A number without trailing zeros, at most 4 decimals (curve.rs `num`).
function num(v) {
    var r = Math.round(v * 1e4) / 1e4
    if (r === 0) return "0"
    return String(r)
}
function canonicalCurve(c) {
    switch (c.kind) {
    case "cubic":
        if (c.points.length === 6)
            return "cubic-bezier(" + [c.points[0], c.points[1], c.points[2], c.points[3]].map(num).join(", ") + ")"
        var segs = []
        for (var i = 0; i < c.points.length; i += 6) segs.push(c.points.slice(i, i + 6).map(num).join(" "))
        return "segments(" + segs.join(", ") + ")"
    case "spring": return "spring(" + num(c.response) + "ms, " + num(c.bounce) + ")"
    case "steps": return "steps(" + c.n + ")"
    case "linear": return "linear"
    }
    return ""
}
// The value as it is written back: a preset or a pack's name as itself, a curve in its canonical form.
function canonical(parsed) {
    if (!parsed || !parsed.ok) return ""
    if (parsed.type === "preset" || parsed.type === "named") return parsed.id
    return canonicalCurve(parsed.curve)
}

// --- sampling -------------------------------------------------------------------------------------------------------------
function bez(t, a, b, c, d) {
    var u = 1 - t
    return u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
}
// Progress at time x of cubic segments (x(t) monotonic: bisection, as curve.rs `sample_cubic`).
function sampleCubic(c, x) {
    var x0 = 0, y0 = 0
    for (var i = 0; i < c.length; i += 6) {
        var c1x = c[i], c1y = c[i + 1], c2x = c[i + 2], c2y = c[i + 3], ex = c[i + 4], ey = c[i + 5]
        if (x <= ex || ex >= 1) {
            if (ex - x0 < 1e-12) return ey
            var lo = 0, hi = 1
            for (var k = 0; k < 40; k++) {
                var mid = 0.5 * (lo + hi)
                if (bez(mid, x0, c1x, c2x, ex) < x) lo = mid
                else hi = mid
            }
            return bez(0.5 * (lo + hi), y0, c1y, c2y, ey)
        }
        x0 = ex
        y0 = ey
    }
    return 1
}

// The spring of §4: mass 1, stiffness (2π/T)², damping 4π(1−b)/T (b ≥ 0) or 4π/(T(1+b)) (b < 0). T in ms.
function springParams(responseMs, bounce) {
    var T = responseMs / 1000
    var k = Math.pow(2 * Math.PI / T, 2)
    var c = bounce >= 0 ? 4 * Math.PI * (1 - bounce) / T : 4 * Math.PI / (T * (1 + bounce))
    return { stiffness: k, damping: c, zeta: c / (2 * Math.sqrt(k)), omega: Math.sqrt(k) }
}
// Back from stiffness/damping (the Advanced fields): {response ms, bounce}.
function fromStiffness(stiffness, damping) {
    var w = Math.sqrt(Math.max(stiffness, 1e-6))
    var T = 2 * Math.PI / w
    var zeta = damping / (2 * w)
    var bounce = zeta <= 1 ? 1 - zeta : 1 / zeta - 1
    return { response: T * 1000, bounce: bounce }
}
// Position at t ms from rest at 0 toward 1, with no initial velocity.
function springAt(responseMs, bounce, tMs) {
    var sp = springParams(responseMs, bounce)
    var t = tMs / 1000, z = sp.zeta, w = sp.omega
    if (Math.abs(z - 1) < 1e-6) return 1 - Math.exp(-w * t) * (1 + w * t)
    if (z < 1) {
        var wd = w * Math.sqrt(1 - z * z)
        return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + (z * w / wd) * Math.sin(wd * t))
    }
    var s = Math.sqrt(z * z - 1)
    var r1 = -w * (z - s), r2 = -w * (z + s)
    return 1 - (r2 * Math.exp(r1 * t) - r1 * Math.exp(r2 * t)) / (r2 - r1)
}
// Overshoot (fraction above 1) and settle time (ms after which |x − 1| < 0.001 for good), sampled every ms.
function springStats(responseMs, bounce) {
    var sp = springParams(responseMs, bounce)
    var over = sp.zeta < 1 ? Math.exp(-Math.PI * sp.zeta / Math.sqrt(1 - sp.zeta * sp.zeta)) : 0
    var limit = Math.max(responseMs * 12, 1000), settle = 0
    for (var t = 0; t <= limit; t += 1)
        if (Math.abs(springAt(responseMs, bounce, t) - 1) >= 0.001) settle = t + 1
    return { overshoot: over, settleMs: settle, stiffness: sp.stiffness, damping: sp.damping }
}

// y at time x ∈ [0, 1] of a curve that is a function of time alone; a spring is sampled over `spanMs` (its plot's width).
function sample(c, x, spanMs) {
    var t = Math.max(0, Math.min(1, x))
    switch (c.kind) {
    case "linear": return t
    case "steps": return t >= 1 ? 1 : Math.floor(t * c.n) / c.n
    case "cubic": return sampleCubic(c.points, t)
    case "spring": return springAt(c.response, c.bounce, t * (spanMs || c.response))
    }
    return t
}
// How long the plot of a curve runs: a timed curve over its duration, a spring until it has settled.
function spanOf(c, ms) {
    if (c.kind === "spring") return Math.max(springStats(c.response, c.bounce).settleMs, c.response)
    return ms || 0
}
// The highest and lowest y of a curve (overshoot band labels): {max, min}.
function extent(c) {
    if (c.kind === "spring") {
        var st = springStats(c.response, c.bounce)
        return { max: 1 + st.overshoot, min: 0 }
    }
    if (c.kind !== "cubic") return { max: 1, min: 0 }
    var mx = 1, mn = 0
    for (var i = 0; i <= 200; i++) { var y = sampleCubic(c.points, i / 200); mx = Math.max(mx, y); mn = Math.min(mn, y) }
    return { max: mx, min: mn }
}

// --- the curve in effect from the theme document --------------------------------------------------------------------------
// `motion.curve.<role>` (W59.1's token: {kind, ms, points|response+bounce|spring+damping|n}) when published; until then
// today's tokens (`motion.kind`, `motion.timed.<role>_curve`/`_ms`, `motion.spring.*`), as W59.2's Theme readers do.
// Result: {curve, ms} or null (no motion).
function fromToken(c) {
    switch (c.kind) {
    case "cubic": return { curve: { kind: "cubic", points: c.points }, ms: c.ms }
    case "spring": return { curve: { kind: "spring", response: c.response, bounce: c.bounce }, ms: c.ms }
    case "spring_q": return { curve: { kind: "spring_q", spring: c.spring, damping: c.damping }, ms: c.ms }
    case "steps": return { curve: { kind: "steps", n: c.n }, ms: c.ms }
    case "linear": return { curve: { kind: "linear" }, ms: c.ms }
    }
    return null
}
// What the profile alone would run on for a role (K83 `motion.profile_curve.<role>`: no user curve or duration), {curve,
// ms} or null (no motion). The resolved curve stands in only on a daemon that does not publish it yet.
function profileCurve(tokens, role) {
    var c = (tokens || ({}))["motion.profile_curve." + role]
    if (c && typeof c === "object" && c.kind) return fromToken(c)
    return inEffect(tokens, role)
}
function inEffect(tokens, role) {
    var t = tokens || ({})
    var c = t["motion.curve." + role]
    if (c && typeof c === "object" && c.kind) return fromToken(c)
    var kind = t["motion.kind"]
    if (kind === "none") return null
    if (kind === "spring")
        return { curve: { kind: "spring_q", spring: t["motion.spring.spring"], damping: t["motion.spring.damping"] }, ms: 0 }
    var pts = t["motion.timed." + role + "_curve"]
    if (Array.isArray(pts) && pts.length >= 6) return { curve: { kind: "cubic", points: pts }, ms: t["motion.timed." + role + "_ms"] }
    return null
}
// A short text of a curve for a line or an accessible name: the canonical form ("" for spring_q).
function describe(c) { return c ? canonicalCurve(c) : "" }
