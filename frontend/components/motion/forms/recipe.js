.pragma library
.import "../../../core/motion/curves.js" as C

// A recipe's tracks evaluated at one progress (W59.7, K83; brief docs/ux/motion-engine.md §5 "Recipes"): the math of
// forms/Recipe.qml, shared with Settings' recipe preview so both draw the same frames. The daemon validated the token
// (`motion.recipe.<id>`: {tracks: [{prop, keys: [[p, v], …] ending at [1, rest], curve, unit}], pivot, base, layer, …});
// nothing here re-checks it beyond guarding what a spring's overshoot could push past a physical bound. No timers, no
// allocation but the frame's result: it runs only while progress moves (Ma).

// Every prop's rest (identity) value — the frame at p = 1.
var REST = { opacity: 1, scale: 1, scale_x: 1, scale_y: 1, translate_along: 0, translate_across: 0, rotate_x: 0,
             rotate_y: 0, rotate_z: 0, skew_x: 0, skew_y: 0, blur: 0, clip_inset: 0, clip_iris: 1, clip_wipe: 1 }
// QQuickRotation's distance to the plane: rotate_x/rotate_y look as a QML Rotation (and `flip`) does.
var PLANE = 1024

// A list as the token holds it: a JS array, or a sequence a document store hands over (Settings' Store).
function isList(x) { return !!x && typeof x === "object" && typeof x.length === "number" }

// The token prepared once (per recipe): its tracks with their curves prepared, and what it needs drawn.
function prepare(token) {
    var out = { ok: false, tracks: [], pivot: "centre", base: "", blurMax: 0, clip: false, layer: false }
    if (!token || token.ok !== true || !isList(token.tracks)) return out
    out.ok = true
    out.pivot = token.pivot || "centre"
    out.base = token.base || ""
    for (var i = 0; i < token.tracks.length; i++) {
        var t = token.tracks[i]
        if (!t || !isList(t.keys) || t.keys.length === 0 || REST[t.prop] === undefined) continue
        out.tracks.push({ prop: t.prop, keys: t.keys, px: t.unit === "px", c: t.curve ? C.prepare(t.curve) : null })
        if (t.prop === "blur") {
            for (var j = 0; j < t.keys.length; j++) out.blurMax = Math.max(out.blurMax, t.keys[j][1])
        }
        if (t.prop.indexOf("clip_") === 0) out.clip = true
    }
    out.layer = out.blurMax > 0 || out.clip
    return out
}

// One track at p: the keys' segment p falls in, eased by the track's curve (CSS keyframes: per segment), held before
// the first key and after the last.
function trackAt(t, p) {
    var k = t.keys, n = k.length
    if (p <= k[0][0]) return k[0][1]
    if (p >= k[n - 1][0]) return k[n - 1][1]
    for (var i = 0; i + 1 < n; i++) {
        var a = k[i], b = k[i + 1]
        if (p < b[0]) {
            var span = b[0] - a[0]
            if (span <= 1e-9) return b[1]
            var x = (p - a[0]) / span
            var e = t.c ? C.at(t.c, x) : x
            return a[1] + (b[1] - a[1]) * e
        }
    }
    return k[n - 1][1]
}

// Every prop at p (p clamped to 0…1: a recipe draws its own overshoot in its keys), with the physical guards.
function evaluate(prep, p) {
    var v = {}
    for (var r in REST) v[r] = REST[r]
    v.px_along = false
    v.px_across = false
    if (!prep || !prep.ok) return v
    p = Math.max(0, Math.min(1, p))
    for (var i = 0; i < prep.tracks.length; i++) {
        var t = prep.tracks[i]
        v[t.prop] = trackAt(t, p)
        if (t.prop === "translate_along") v.px_along = t.px
        if (t.prop === "translate_across") v.px_across = t.px
    }
    v.opacity = Math.max(0, Math.min(1, v.opacity))
    v.scale = Math.max(0, v.scale); v.scale_x = Math.max(0, v.scale_x); v.scale_y = Math.max(0, v.scale_y)
    v.blur = Math.max(0, v.blur)
    v.clip_inset = Math.max(0, Math.min(0.5, v.clip_inset))
    v.clip_iris = Math.max(0, Math.min(1, v.clip_iris))
    v.clip_wipe = Math.max(0, Math.min(1, v.clip_wipe))
    return v
}

// The point things turn and scale about, in the host's coordinates: its centre, the middle of the edge it comes from,
// or the origin (the pressed module's centre; the edge's middle without one).
function pivot(prep, w, h, edge, origin) {
    var e = edge === "bottom" ? [w / 2, h] : edge === "left" ? [0, h / 2] : edge === "right" ? [w, h / 2] : [w / 2, 0]
    if (prep.pivot === "edge") return e
    if (prep.pivot === "origin") {
        if (origin && origin.width > 0 && origin.height > 0)
            return [origin.x + origin.width / 2, origin.y + origin.height / 2]
        return e
    }
    return [w / 2, h / 2]
}

// 4×4 row-major products, enough for one frame's matrix.
function mul(a, b) {
    var o = new Array(16)
    for (var r = 0; r < 4; r++)
        for (var c = 0; c < 4; c++)
            o[r * 4 + c] = a[r * 4] * b[c] + a[r * 4 + 1] * b[4 + c] + a[r * 4 + 2] * b[8 + c] + a[r * 4 + 3] * b[12 + c]
    return o
}
function translate(x, y) { return [1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, 0, 0, 0, 0, 1] }

// The frame's transform as 16 row-major numbers (Qt.matrix4x4's order), identity at rest: about the pivot, scale, then
// skew, then the turns (x, then y, then z) projected as QQuickRotation does; then the translation.
function matrix(prep, v, w, h, edge, origin) {
    var rad = Math.PI / 180
    var horizontal = edge === "left" || edge === "right"
    // Along: toward the edge the surface comes from; across: right (top/bottom edges) or down (left/right).
    var ax = edge === "left" ? -1 : edge === "right" ? 1 : 0
    var ay = edge === "top" || edge === "" || edge === undefined ? -1 : edge === "bottom" ? 1 : 0
    var along = v.translate_along * (v.px_along ? 1 : (horizontal ? w : h))
    var across = v.translate_across * (v.px_across ? 1 : (horizontal ? h : w))
    var tx = ax * along + (horizontal ? 0 : across)
    var ty = ay * along + (horizontal ? across : 0)

    var sx = v.scale * v.scale_x, sy = v.scale * v.scale_y
    var kx = Math.tan(v.skew_x * rad), ky = Math.tan(v.skew_y * rad)
    // The linear part before the turns: skew · scale.
    var l00 = sx, l01 = kx * sy, l10 = ky * sx, l11 = sy

    var cx = Math.cos(v.rotate_x * rad), snx = Math.sin(v.rotate_x * rad)
    var cy = Math.cos(v.rotate_y * rad), sny = Math.sin(v.rotate_y * rad)
    var cz = Math.cos(v.rotate_z * rad), snz = Math.sin(v.rotate_z * rad)
    // R = Rz · Ry · Rx (rows 0–2, columns x y; the z column is not needed for points on the plane).
    var r00 = cz * cy, r01 = cz * sny * snx - snz * cx
    var r10 = snz * cy, r11 = snz * sny * snx + cz * cx
    var r20 = -sny, r21 = cy * snx
    var rot = [r00, r01, 0, 0,
               r10, r11, 0, 0,
               0, 0, 1, 0,
               -r20 / PLANE, -r21 / PLANE, 0, 1]
    var lin = [l00, l01, 0, 0, l10, l11, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    var pv = pivot(prep, w, h, edge, origin)
    var m = mul(translate(pv[0] + tx, pv[1] + ty), mul(rot, mul(lin, translate(-pv[0], -pv[1]))))
    return m
}

// The clip at v, in the host's coordinates: the box left by inset and wipe, and the iris circle (r < 0: none).
function clip(prep, v, w, h, edge, origin) {
    var i = v.clip_inset
    var x0 = i * w, y0 = i * h, x1 = w - i * w, y1 = h - i * h
    var f = v.clip_wipe
    if (f < 1) {
        if (edge === "bottom") y0 = Math.max(y0, h - f * h)
        else if (edge === "left") x1 = Math.min(x1, f * w)
        else if (edge === "right") x0 = Math.max(x0, w - f * w)
        else y1 = Math.min(y1, f * h)
    }
    var out = { x: x0, y: y0, w: Math.max(0, x1 - x0), h: Math.max(0, y1 - y0), cx: 0, cy: 0, r: -1 }
    if (v.clip_iris < 1) {
        var pv = pivot(prep, w, h, edge, origin)
        var far = 0
        var corners = [[0, 0], [w, 0], [0, h], [w, h]]
        for (var k = 0; k < 4; k++)
            far = Math.max(far, Math.hypot(corners[k][0] - pv[0], corners[k][1] - pv[1]))
        out.cx = pv[0]; out.cy = pv[1]; out.r = v.clip_iris * far
    }
    return out
}
