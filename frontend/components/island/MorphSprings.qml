import QtQuick
import Quickshell
import "../../core"

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

    readonly property real cap: Math.max(0.03, Math.min(0.08, 0.03 + (0.45 - Theme.damping) * 0.26))
    readonly property real squash: Theme.springOn
        ? Theme.tok("motion.spring.squash", Math.max(0, Math.min(0.07, (0.45 - Theme.damping) * 0.35))) : 0
    function soft(v, to, span) {
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
        if (axis === 0) scx = span(cxTo, cx, scx, lcx)
        else if (axis === 1) sw = span(wTo, w, sw, lw)
        else sh = span(hTo, h, sh, lh)
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
    function snapIfOff() { if (!on) snap() }
    function snap() {
        driver.running = false
        cx = cxTo; w = wTo; h = hTo
        vcx = 0; vw = 0; vh = 0
        scx = 0; sw = 0; sh = 0
        lcx = cxTo; lw = wTo; lh = hTo
        publish()
    }
    // The start of a morph: values set, no velocity, nothing runs until a target moves.
    function place(c, ww, hh) {
        driver.running = false
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
        if (debugLog) { frames++; stepMs += Date.now() - t0 }
        if (done) {
            driver.running = false
            if (debugLog) { console.log("morph-springs settled frames=" + frames + " stepMs=" + stepMs); frames = 0; stepMs = 0 }
        }
    }
    property FrameAnimation driver: FrameAnimation {
        running: false
        onTriggered: ms.advance(frameTime)
    }
}
