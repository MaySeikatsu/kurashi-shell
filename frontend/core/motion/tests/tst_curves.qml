import QtQuick
import QtTest
import "../curves.js" as C
import "../../ease.js" as Ease

// curves.js against what it replaces (W59.2): ease.js's bisection for today's bezierCurve lists, MorphSprings' K42 loop
// for spring_q, plus the spring closed form, steps, retarget and scrub parsing. Offscreen, no shell:
//   QT_QPA_PLATFORM=offscreen qmltestrunner -input frontend/core/motion/tests
TestCase {
    name: "curves"

    // Today's curves (tokens.rs §motion and the looks): K74's four, rubber, fluent, a staircase.
    readonly property var today: [
        [0.38, 1.21, 0.22, 1, 1, 1],
        [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1],
        [0.42, 1.67, 0.21, 0.9, 1, 1],
        [0.34, 0.8, 0.34, 1, 1, 1],
        [0.34, 1.56, 0.64, 1, 1, 1],
        [0.1, 0.9, 0.2, 1, 1, 1],
        [0, 0, 0, 1, 1, 1],
        [0.3, 0, 1, 1, 1, 1]
    ]
    function stair(n) {
        var c = []
        var r = function (v) { return Math.round(v * 1e4) / 1e4 }
        for (var k = 0; k < n; k++) {
            var x0 = k / n, x1 = (k + 1) / n, xj = x0 + Math.min(x1 - x0, 0.002) / 2
            c.push(r(x0), r(x0), r(xj), r(x1), r(xj), r(x1))
            c.push(r(xj), r(x1), r(x1), r(x1), r(x1), r(x1))
        }
        return c
    }

    function test_cubic_matches_ease() {
        var worst = 0
        for (var i = 0; i < today.length; i++) {
            var p = C.prepare({ kind: "cubic", ms: 500, points: today[i] })
            for (var k = 0; k <= 1000; k++) {
                var x = k / 1000
                var d = Math.abs(C.at(p, x) - Ease.at(today[i], x))
                if (d > worst) worst = d
            }
        }
        // ease.js stops at 24 bisections (t to 6e-8): agreement to float noise, far below a pixel of any travel.
        verify(worst < 2e-6, "worst " + worst)
    }

    function test_staircase_matches_ease() {
        var c = stair(8)
        var p = C.prepare(c)
        var worst = 0
        for (var k = 0; k <= 997; k++) {
            var x = k / 997
            var d = Math.abs(C.at(p, x) - Ease.at(c, x))
            // (inside a 0.001-wide jump both are mid-ramp; elsewhere equal)
            var inJump = Math.abs(x * 8 - Math.round(x * 8)) * 0.125 < 0.0011
            if (!inJump && d > worst) worst = d
        }
        verify(worst < 1e-6, "worst " + worst)
    }

    function test_bare_list_and_token_are_one() {
        var a = C.prepare(today[0]), b = C.prepare({ kind: "cubic", ms: 0, points: today[0] })
        compare(C.at(a, 0.37), C.at(b, 0.37))
    }

    function test_steps() {
        var p = C.prepare({ kind: "steps", ms: 64, n: 4 })
        compare(C.at(p, 0), 0)
        compare(C.at(p, 0.01), 0.25)
        compare(C.at(p, 0.25), 0.25)
        compare(C.at(p, 0.26), 0.5)
        compare(C.at(p, 1), 1)
    }

    function test_none_and_unknown() {
        compare(C.prepare(null).kind, "none")
        compare(C.prepare({ kind: "bogus" }).kind, "none")
        compare(C.prepare({ kind: "none" }).kind, "none")
    }

    // The K42 loop exactly as MorphSprings writes it (one axis), against springQStep.
    function test_spring_q_bit_exact() {
        var ks = [[4.0, 0.45], [3.2, 0.26], [4.0 * 1.3, 0.45 * 1.25]]
        for (var j = 0; j < ks.length; j++) {
            var k = ks[j][0], c = ks[j][1]
            var x0 = 12, v0 = 0, to = 380, acc = 0
            var st = { x: 12, v: 0, acc: 0 }
            var dts = [16, 7, 25, 16.6, 33, 16, 50, 3, 16, 16]
            for (var f = 0; f < 300; f++) {
                var dt = dts[f % dts.length]
                acc += dt; st.acc += dt
                while (acc >= 16) {
                    v0 = v0 + k * (to - x0) - c * v0; x0 += v0 * 0.016
                    acc -= 16
                }
                C.springQStep(st, to, k, c)
                if (st.x !== x0 || st.v !== v0) fail("frame " + f + ": " + st.x + " vs " + x0)
            }
        }
    }

    function test_spring_closed_form() {
        // critically damped (bounce 0): no overshoot; bouncy: overshoots, then settles.
        var g = C.prepare({ kind: "spring", ms: 450, response: 450, bounce: 0 })
        var b = C.prepare({ kind: "spring", ms: 550, response: 550, bounce: 0.45 })
        var o = { d: 0, v: 0 }, maxG = 0, maxB = 0
        for (var t = 0; t < 3000; t += 8) {
            C.springEval(g, -1, 0, t, o); maxG = Math.max(maxG, 1 + o.d)
            C.springEval(b, -1, 0, t, o); maxB = Math.max(maxB, 1 + o.d)
        }
        verify(maxG <= 1 + 1e-9, "critical overshoots " + maxG)
        verify(maxB > 1.05, "bouncy does not overshoot " + maxB)
        verify(g.settle > 200 && g.settle < 3000, "settle " + g.settle)
        // velocity is the derivative of the displacement
        C.springEval(b, -1, 0.5, 120, o)
        var d1 = o.d, v1 = o.v
        C.springEval(b, -1, 0.5, 121, o)
        verify(Math.abs((o.d - d1) / 0.001 - v1) < 0.05 * Math.max(1, Math.abs(v1)), "v " + v1)
        // overdamped (negative bounce) settles without crossing
        var od = C.prepare({ kind: "spring", ms: 500, response: 500, bounce: -0.4 })
        C.springEval(od, -1, 0, 200, o)
        verify(o.d < 0 && o.d > -1)
    }

    function test_retarget_matches_slope() {
        var p = C.prepare({ kind: "cubic", ms: 500, points: today[0] })
        var r = C.retarget(p, 0.8)
        verify(Math.abs(C.slope(r, 0) - 0.8) < 1e-9, "slope " + C.slope(r, 0))
        compare(C.at(r, 1), 1)
        // a flat-started curve gets a handle to carry the slope; clamped to the token range
        var f = C.retarget(C.prepare({ kind: "cubic", ms: 300, points: [0, 0, 0, 1, 1, 1] }), 100)
        verify(f.points[1] <= 2)
        compare(C.retarget(C.prepare({ kind: "steps", n: 3 }), 2).kind, "steps")
    }

    function test_spring_fraction_ends() {
        var q = C.prepare({ kind: "spring_q", spring: 4.0, damping: 0.45 })
        compare(C.at(q, 0), 0)
        compare(C.at(q, 1), 1)
        var m = C.at(q, 0.5)
        verify(m > 0.5 && m < 1.2, "mid " + m)
    }
}
