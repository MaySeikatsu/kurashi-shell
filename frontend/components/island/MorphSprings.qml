import QtQuick
import Quickshell
import "../../core"
import "../../core/motion/curves.js" as C

// The springs of one morphing shape (W34, docs/ux/motion.md; Capsule's animator): three axes in px — `cx` (the shape's
// centre along the bar), `w` (its extent along the bar) and `h` (how far it reaches out of the bar, its foot) — each a
// damped spring towards its target (`cxTo`, `wTo`, `hTo`), so a new target at any moment (open, close, a retarget to
// another panel) keeps the current place and velocity. On the way out (`expanding`) the travel and the width lead and the
// foot follows; on the way back the foot leads (K42). Constants from tokens only (rule 4): `Theme.spring`/`Theme.damping`
// in QML SpringAnimation's units, integrated the way SpringAnimation does (16 ms steps: v += k·Δ − c·v, x += v·0.016),
// so the feel is the island's of session 9.
// What it adds over SpringAnimation (which exposes neither velocity nor landing, and once stopped mid-way, B32):
// - `*Out`: the value with its overshoot past the target soft-limited (tanh) to `cap` of the travel — 3 % for a
//   near-critical spring (calm), up to 8 % for a bouncy one (lively), derived from `Theme.damping`;
// - `squeeze`: squash & stretch (I113) — the fraction the shape narrows while its foot moves fast (negative: it bulges as
//   it lands and rebounds), `squash` × the foot's speed; `squash` is the token `motion.spring.squash` (a contract request,
//   CONTRACT-CHANGE), else derived from the damping (0 for calm's, ~0.066 for lively's);
// - `neckScale`: the neck's wobble on landing (1 at rest; thinner while the foot overshoots, fuller as it rebounds).
// Timed (K74, K83: the profile's open curve is a cubic, steps or linear — expressive, the looks): every axis runs the
// curve instead of its spring (core/motion/curves.js) — from where it is to its target, `Theme.motionCurve("open")` on
// the way out, `"close"` back, over the curve's `ms`; a new target starts a new curve from where the axis stands. The
// curve's own overshoot is the bounce (no soft limit, no squash). A `spring` curve (closed form, W59 packs) runs each
// axis on it, keeping velocity. KURASHI_MOTION_SCRUB=<p> holds every axis at p of its travel (`scrubTo`).
// `on` false (motion off, or before the first frame) snaps every axis to its target. The driver (a FrameAnimation) runs
// only while an axis is still moving: idle, nothing runs (Ma). `place()` sets the values without motion (the start).
QtObject {
    id: ms
    property bool on: true
    property bool expanding: true
    property real cxTo: 0
    property real wTo: 0
    property real hTo: 0
    // Values (raw: past the target while overshooting) and velocities (px/s).
    property real cx: 0
    property real w: 0
    property real h: 0
    property real vcx: 0
    property real vw: 0
    property real vh: 0
    // The travel of each axis since its last target change (signed), for the soft limit and the progress.
    property real scx: 0
    property real sw: 0
    property real sh: 0
    readonly property bool settled: !driver.running

    // K42's soft limit (3 % for calm's damping … 8 % for lively's) is the morph's own; a profile's overshoot cap (K83
    // accent; W59.1 publishes 1 = none of its own, 0 with motion off) only tightens it — never to 0: the Stage sizes its
    // window by the cap, and motion off keeps today's 3 %. Squash: the accent (lively's 0.06).
    readonly property real k42Cap: Math.max(0.03, Math.min(0.08, 0.03 + (0.45 - Theme.damping) * 0.26))
    readonly property real accentCap: Theme.motionAccent("overshoot_cap")
    readonly property real cap: accentCap > 0 ? Math.min(accentCap, k42Cap) : k42Cap
    readonly property real squash: Theme.motionAccent("squash")
    // The kind of the profile's open curve picks the runner: "cubic"/"steps"/"linear" timed, "spring" closed form,
    // "spring_q" K42's integrator (`advance`), "none" (with `on` false) a cut.
    readonly property string kind: C.prepare(Theme.motionCurve("open")).kind
    readonly property bool timed: C.timedKind(kind)
    readonly property bool sprung: kind === "spring"
    function curveNow() { return C.prepare(Theme.motionCurve(expanding ? "open" : "close")) }
    // Timed: each axis's start, the time it has run (ms) and its length, and the curve it runs (closed-form springs:
    // the displacement and velocity each axis started from).
    property var t0: [0, 0, 0]
    property var tEl: [0, 0, 0]
    property var tV0: [0, 0, 0]
    property real tDur: 1
    property var tCurve: C.prepare(null)
    property var sp: ({ d: 0, v: 0 })
    readonly property real scrub: C.scrub(Quickshell.env("KURASHI_MOTION_SCRUB"))
    function soft(v, to, span) {
        if (timed || sprung) return v
        var over = (v - to) * (span >= 0 ? 1 : -1)
        var lim = cap * Math.abs(span)
        if (over <= 0 || lim < 0.5) return over > 0 ? to : v
        return to + (span >= 0 ? 1 : -1) * lim * Math.tanh(over / lim)
    }
    // The outputs, published by the springs themselves (never bindings on the targets: a target read inside an output's
    // binding would move the travel that binding is computing).
    property real cxOut: 0
    property real wOut: 0
    property real hOut: 0
    // How far each axis has come along its current travel, 0..1 (1 with no travel).
    property real pcx: 1
    property real pw: 1
    property real ph: 1
    property real squeeze: 0
    property real neckScale: 1
    function prog(v, to, span) { return Math.abs(span) < 0.5 ? 1 : Math.max(0, Math.min(1, 1 - (to - v) / span)) }
    function publish() {
        cxOut = soft(cx, cxTo, scx)
        wOut = Math.max(0, soft(w, wTo, sw))
        hOut = soft(h, hTo, sh)
        pcx = prog(cx, cxTo, scx)
        pw = prog(w, wTo, sw)
        ph = prog(h, hTo, sh)
        squeeze = squash > 0 ? squash * Math.max(-1, Math.min(1, vh / Math.max(600, Math.abs(sh) * 5))) : 0
        neckScale = squash > 0 && expanding && Math.abs(sh) > 4
            ? 1 - Math.max(-0.45, Math.min(0.6, (h - hTo) / Math.abs(sh) * 7 * squash / 0.07)) : 1
    }

    // Spring constants per axis and direction: [k, c] multipliers of Theme.spring / Theme.damping (the island's, K42).
    // `stiffness` scales every spring keeping its damping ratio (a small shape, a peek, settles sooner): k × s, c × √s.
    property real stiffness: 1
    function kOf(axis) { return stiffness * Theme.spring * (expanding ? [0.75, 1.3, 1.0][axis] : [1.2, 1.2, 1.6][axis]) }
    function cOf(axis) { return Math.min(0.95, Math.sqrt(stiffness) * Theme.damping * (expanding ? [1.05, 1.0, 1.25][axis] : [1.1, 1.25, 1.0][axis])) }

    onCxToChanged: retarget(0)
    onWToChanged: retarget(1)
    onHToChanged: retarget(2)
    onOnChanged: if (!on) snap()
    function retarget(axis) {
        // Off: snap, after the binding that moved the target has finished (a target read inside an output's binding
        // would otherwise write the value that binding is computing).
        if (!on) { Qt.callLater(snapIfOff); return }
        if (scrub >= 0) { scrubTo(axis); lcx = cxTo; lw = wTo; lh = hTo; publish(); return }
        if (axis === 0) scx = span(cxTo, cx, scx, lcx)
        else if (axis === 1) sw = span(wTo, w, sw, lw)
        else sh = span(hTo, h, sh, lh)
        if (timed || sprung) {
            t0[axis] = [cx, w, h][axis]
            tEl[axis] = 0
            tV0[axis] = [vcx, vw, vh][axis]
            var cv = curveNow()
            // (a peek's stiffer spring keeps its damping ratio: the response shortens by √stiffness)
            if (sprung && stiffness !== 1)
                cv = C.prepare({ kind: "spring", ms: cv.ms, response: cv.response / Math.sqrt(stiffness), bounce: cv.bounce })
            tCurve = cv
            tDur = Math.max(1, cv.ms)
        }
        lcx = cxTo; lw = wTo; lh = hTo
        if (!driver.running) { acc = 0; fresh = true }
        driver.running = true
        publish()
    }
    // The travel a new target gives an axis: from where it is now, unless the target only moved on a little in the same
    // direction (a card that grows while it is out): then the travel keeps its start, so the progress does not fall back.
    property real lcx: 0
    property real lw: 0
    property real lh: 0
    function span(to, v, old, lastTo) {
        var start = lastTo - old
        if (driver.running && Math.abs(old) >= 0.5 && Math.abs(to - lastTo) < 0.25 * Math.abs(old) && (to - start) * old > 0)
            return to - start
        return to - v
    }
    // Scrubbed (KURASHI_MOTION_SCRUB, tests): the axis stands at p of its travel and nothing runs. The travel starts where
    // the axis stood when it began moving this way (a target that moves on keeps that start; a reversal starts at the
    // end the other way would have reached).
    property var sFrom: [0, 0, 0]
    property var sDir: [true, true, true]
    property var sHeld: [false, false, false]
    function scrubTo(axis) {
        var to = [cxTo, wTo, hTo][axis]
        if (!sHeld[axis] || sDir[axis] !== expanding) {
            sFrom[axis] = sHeld[axis] ? [lcx, lw, lh][axis] : [cx, w, h][axis]
            sDir[axis] = expanding
            sHeld[axis] = true
        }
        var a = sFrom[axis], cv = curveNow()
        var f = scrub >= 1 ? 1 : cv.kind === "spring_q" || !(timed || sprung)
            ? C.springAtFraction(cv, scrub, kOf(axis), cOf(axis)) : C.at(cv, scrub)
        var v = scrub >= 1 ? to : a + (to - a) * f
        driver.running = false
        if (axis === 0) { cx = v; vcx = 0; scx = to - a }
        else if (axis === 1) { w = v; vw = 0; sw = to - a }
        else { h = v; vh = 0; sh = to - a }
    }
    // (Called later: the object may be gone by then, a toast whose card was removed.)
    function snapIfOff() { if (typeof snap === "function" && !on) snap() }
    function snap() {
        driver.running = false
        sHeld = [false, false, false]
        cx = cxTo; w = wTo; h = hTo
        vcx = 0; vw = 0; vh = 0
        scx = 0; sw = 0; sh = 0
        lcx = cxTo; lw = wTo; lh = hTo
        // S21: every axis's timed/closed-form travel ends here too — a later target change on ONE axis restarts the
        // runner for all three, and an axis left with its old start (t0) would run that travel again (the card that
        // jumped back to its origin's width once a sheet form had landed and its height moved).
        t0 = [cxTo, wTo, hTo]; tEl = [tDur, tDur, tDur]; tV0 = [0, 0, 0]
        publish()
    }
    // The start of a morph: values set, no velocity, nothing runs until a target moves.
    function place(c, ww, hh) {
        driver.running = false
        sHeld = [false, false, false]
        cx = c; w = ww; h = hh
        vcx = 0; vw = 0; vh = 0
        scx = 0; sw = 0; sh = 0
        lcx = cxTo; lw = wTo; lh = hTo
        publish()
    }

    // Test only (KURASHI_STAGE_DEBUG=1): the frames each run took and the JS time spent stepping them.
    readonly property bool debugLog: Quickshell.env("KURASHI_STAGE_DEBUG") === "1"
    property int frames: 0
    property real stepMs: 0
    property real acc: 0
    property bool fresh: false
    function advance(dt) {
        if (timed) { advanceTimed(dt); return }
        if (sprung) { advanceSpring(dt); return }
        var t0 = debugLog ? Date.now() : 0
        // The first frame of a run counts one step: the driver's time since it last ran is not motion.
        acc += (fresh ? 0.016 : Math.min(dt, 0.05)) * 1000
        fresh = false
        var x0 = cx, x1 = w, x2 = h, v0 = vcx, v1 = vw, v2 = vh
        var k0 = kOf(0), k1 = kOf(1), k2 = kOf(2), c0 = cOf(0), c1 = cOf(1), c2 = cOf(2)
        while (acc >= 16) {
            v0 = v0 + k0 * (cxTo - x0) - c0 * v0; x0 += v0 * 0.016
            v1 = v1 + k1 * (wTo - x1) - c1 * v1; x1 += v1 * 0.016
            v2 = v2 + k2 * (hTo - x2) - c2 * v2; x2 += v2 * 0.016
            acc -= 16
        }
        var done = Math.abs(cxTo - x0) < 0.3 && Math.abs(wTo - x1) < 0.3 && Math.abs(hTo - x2) < 0.3
            && Math.abs(v0) < 4 && Math.abs(v1) < 4 && Math.abs(v2) < 4
        if (done) { x0 = cxTo; x1 = wTo; x2 = hTo; v0 = 0; v1 = 0; v2 = 0 }
        vcx = v0; vw = v1; vh = v2
        cx = x0; w = x1; h = x2
        publish()
        if (debugLog) {
            frames++; stepMs += Date.now() - t0
            if (frames % 120 === 0) console.log("morph-springs running frames=" + frames + " d=" + (cxTo - cx).toFixed(2) + "," + (wTo - w).toFixed(2)
                + "," + (hTo - h).toFixed(2) + " v=" + vcx.toFixed(1) + "," + vw.toFixed(1) + "," + vh.toFixed(1))
        }
        if (done) {
            driver.running = false
            if (debugLog) { console.log("morph-springs settled frames=" + frames + " stepMs=" + stepMs); frames = 0; stepMs = 0 }
        }
    }
    function advanceTimed(dt) {
        var step = (fresh ? 0.016 : Math.min(dt, 0.05)) * 1000
        fresh = false
        var to = [cxTo, wTo, hTo], v = [cx, w, h], done = true
        for (var a = 0; a < 3; a++) {
            tEl[a] = Math.min(tDur, tEl[a] + step)
            var p = tEl[a] / tDur
            v[a] = p >= 1 ? to[a] : t0[a] + (to[a] - t0[a]) * C.at(tCurve, p)
            if (p < 1) done = false
        }
        vcx = 0; vw = 0; vh = 0
        cx = v[0]; w = v[1]; h = v[2]
        publish()
        if (done) driver.running = false
    }
    // A closed-form spring per axis (curves.js), from the displacement and velocity it had at its last target.
    function advanceSpring(dt) {
        var step = (fresh ? 0.016 : Math.min(dt, 0.05)) * 1000
        fresh = false
        var to = [cxTo, wTo, hTo], v = [cx, w, h], vel = [0, 0, 0], done = true
        for (var a = 0; a < 3; a++) {
            tEl[a] += step
            C.springEval(tCurve, t0[a] - to[a], tV0[a], tEl[a], sp)
            if (Math.abs(sp.d) < 0.3 && Math.abs(sp.v) < 4) { v[a] = to[a]; vel[a] = 0 }
            else { v[a] = to[a] + sp.d; vel[a] = sp.v; done = false }
        }
        vcx = vel[0]; vw = vel[1]; vh = vel[2]
        cx = v[0]; w = v[1]; h = v[2]
        publish()
        if (done) driver.running = false
    }
    property FrameAnimation driver: FrameAnimation {
        running: false
        onTriggered: ms.advance(frameTime)
    }
}
