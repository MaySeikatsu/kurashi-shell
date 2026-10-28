.pragma library

// A multi-segment cubic bezier easing as QML's `easing.bezierCurve` lists it (K74): segments of (c1x, c1y, c2x, c2y, ex,
// ey), each starting where the last ended, the first at (0, 0) and the last ending at (1, 1). `at(curve, x)` is its y at
// progress x (0..1) — for surfaces driven per frame (MorphSprings, the timed morphs), which cannot use a NumberAnimation.
// x is solved per segment by bisection (x(t) is monotonic in every curve the tokens carry); no allocation per call.
function at(c, x) {
    if (x <= 0) return 0
    if (x >= 1) return 1
    var x0 = 0, y0 = 0
    for (var i = 0; i + 5 < c.length; i += 6) {
        var ex = c[i + 4], ey = c[i + 5]
        if (x <= ex || i + 11 >= c.length) {
            var lo = 0, hi = 1, t = 0.5
            for (var k = 0; k < 24; k++) {
                t = (lo + hi) / 2
                var u = 1 - t
                var bx = u * u * u * x0 + 3 * u * u * t * c[i] + 3 * u * t * t * c[i + 2] + t * t * t * ex
                if (bx < x) lo = t; else hi = t
            }
            var v = 1 - t
            return v * v * v * y0 + 3 * v * v * t * c[i + 1] + 3 * v * t * t * c[i + 3] + t * t * t * ey
        }
        x0 = ex; y0 = ey
    }
    return 1
}
