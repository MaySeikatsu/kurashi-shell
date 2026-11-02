import QtQuick
import Quickshell
import "curves.js" as C

// One value moved to `to` on a curve (K83, docs/ux/motion-engine.md §9; W59 contract "Frontend interfaces"): the motion
// engine's single runner. Timed curves (cubic, steps, linear) run their duration from where the value stands; springs
// keep their velocity through a new target (`spring_q`: K42's 16-ms integrator, today's calm and lively; `spring`: the
// closed form); `none` (or `enabled` false) cuts. One FrameAnimation, running only while the value moves (Ma: idle,
// nothing runs). The curve comes from the owner — Driver reads no tokens, so Settings can preview a draft curve:
//   curves: Theme.motionCurves   ({open, close, fast, effects}: picked by `role`; "auto" = open the opening way)
//   curve: {kind: "cubic", ms: 300, points: […]}   (wins over role/curves)
// Outputs: `value`, `velocity` (units/s), `progress` (eased fraction of the current travel from `from`: 0 as it starts,
// past 1 while a curve overshoots, 1 at rest), `running`, `direction` ("open"/"close", the way the last travel went).
// A 0 → 1 reveal hands its `value` (not `progress`, which restarts at 0 for a close) to a FormHost.
// KURASHI_MOTION_SCRUB=<p> (read once) holds every travel at p: shots by progress, not by sleeping; p = 1 is the rest.
// `track(p)`/`release(v)` hand the travel to a gesture or Settings' scrubber and back.
QtObject {
    id: d
    property real to: 0
    property string role: "auto"
    // Which way opens: a rising value (a reveal 0 → 1) or a falling one.
    property bool openUp: true
    property var curves: null
    property var curve: null
    // spring_q only: the owner's own constants (a Glide's SpringAnimation values); NaN = the curve's.
    property real spring: NaN
    property real damping: NaN
    // spring_q's rest (QML SpringAnimation's rule): velocity and distance both under it, in the value's units.
    property real epsilon: 0.01
    // A retarget mid-flight keeps the velocity (§7): a cubic's first handle takes the current slope. Off: a new travel
    // starts on the curve as written (today's Glide and morphs).
    property bool keepVelocity: true
    property bool enabled: true

    property real value: 0
    property real velocity: 0
    property real progress: 1
    property real from: 0
    property bool running: false
    property string direction: "open"
    // The resolved curve of the current travel (prepared by curves.js) and its kind: "cubic" "steps" "linear" "spring"
    // "spring_q" "none".
    property var active: C.prepare(null)
    readonly property string kind: active.kind
    // Track mode: a gesture owns the value.
    property bool tracking: false
    signal landed(real at)

    readonly property real scrub: C.scrub(Quickshell.env("KURASHI_MOTION_SCRUB"))
    property bool ready: false
    Component.onCompleted: { value = to; from = to; ready = true }
    onToChanged: go()
    onEnabledChanged: if (!enabled) snap(to)

    function curveFor(opening) {
        if (curve) return curve
        if (!curves) return null
        var r = role === "auto" ? (opening ? "open" : "close") : role
        return curves[r] || null
    }
    function k() { return isNaN(spring) ? active.spring : spring }
    function c() { return isNaN(damping) ? active.damping : damping }

    // The end of the current travel: `to`, or the end a release() heads for.
    property real target: 0
    property real elapsed: 0
    property bool fresh: false
    property real startedAt: 0
    property var st: ({ x: 0, v: 0, acc: 0 })
    property var sp: ({ d: 0, v: 0 })
    property real d0: 0
    property real v0: 0
    // Start a travel from where the value stands to `to` (to `end` when given: release()).
    function go(end) {
        if (!ready || tracking) return
        var goal = end === undefined ? to : end
        var dist = goal - value
        var opening = (dist > 0) === openUp
        var next = C.prepare(curveFor(opening))
        if (!enabled || next.kind === "none") { snap(goal); return }
        if (Math.abs(dist) < 1e-4 && !(running && next.kind.indexOf("spring") === 0)) {
            fa.running = false; running = false; value = goal; velocity = 0; progress = 1; from = goal
            return
        }
        direction = opening ? "open" : "close"
        var moving = running
        // A cubic retargeted mid-flight starts with the slope the value has (travels per duration).
        if (moving && keepVelocity && next.kind === "cubic" && Math.abs(dist) > 1e-9 && next.ms > 0)
            next = C.retarget(next, velocity * next.ms / 1000 / dist)
        active = next
        d.target = goal
        from = value
        if (scrub >= 0) { hold(goal); return }
        elapsed = 0
        progress = 0
        if (next.kind === "spring_q") {
            st.x = value; st.v = moving ? velocity : 0; st.acc = 0
        } else if (next.kind === "spring") {
            d0 = value - goal; v0 = moving ? velocity : 0
        } else if (!moving) {
            velocity = 0
        }
        if (!fa.running) { fresh = true; startedAt = Date.now() }
        running = true
        fa.running = true
    }
    function hold(goal) {
        fa.running = false; running = false; velocity = 0
        var f = active.kind === "spring_q" ? C.springAtFraction(active, scrub, k(), c())
            : active.kind === "spring" ? C.springAtFraction(active, scrub) : C.at(active, scrub)
        value = scrub >= 1 ? goal : from + (goal - from) * f
        progress = scrub >= 1 ? 1 : f
    }

    function advance(dt) {
        // The first frame of a run counts the time since the travel began (as QML's animations count from their start:
        // a Glide's spring steps exactly as the SpringAnimation it replaces), not the time since the driver last ran.
        var step = fresh ? Math.max(0, Math.min(50, Date.now() - startedAt)) : Math.min(dt, 0.05) * 1000
        fresh = false
        var goal = target, span = goal - from, done = false
        if (active.kind === "spring_q") {
            st.acc += step
            var kk = k(), cc = c()
            C.springQStep(st, goal, kk, cc)
            if (Math.abs(st.v) < epsilon && Math.abs(goal - st.x) < epsilon) done = true
            else { value = st.x; velocity = st.v }
        } else if (active.kind === "spring") {
            elapsed += step
            C.springEval(active, d0, v0, elapsed, sp)
            var tol = Math.max(1e-4, Math.abs(span) * 1e-3)
            if (Math.abs(sp.d) < tol && Math.abs(sp.v) < tol * 10) done = true
            else { value = goal + sp.d; velocity = sp.v }
        } else {
            var dur = Math.max(1, active.ms)
            elapsed = Math.min(dur, elapsed + step)
            var x = elapsed / dur
            if (x >= 1) done = true
            else {
                value = from + span * C.at(active, x)
                velocity = span * C.slope(active, x) * 1000 / dur
            }
        }
        if (done) {
            value = goal; velocity = 0; progress = 1
            fa.running = false; running = false
            landed(goal)
            return
        }
        progress = Math.abs(span) < 1e-9 ? 1 : (value - from) / span
    }

    // Set without motion (a surface made at rest); `to` is the owner's (a binding stays).
    function snap(v) {
        fa.running = false; running = false; tracking = false
        value = v; from = v; velocity = 0; progress = 1; d.target = v
    }
    // A gesture (or Settings' scrubber) holds the value at fraction p of a travel `a` → `b` (default: the last travel,
    // `from` → `to`; 0 → 1 when there was none); the velocity follows the hand.
    property real ta: 0
    property real tb: 1
    property real tAt: 0
    function track(p, a, b) {
        if (!tracking) {
            ta = a === undefined ? from : a
            tb = b === undefined ? to : b
            if (Math.abs(tb - ta) < 1e-9) { ta = 0; tb = 1 }
        }
        var now = Date.now()
        var v = ta + (tb - ta) * p
        velocity = tracking && now > tAt ? (v - value) * 1000 / (now - tAt) : 0
        tAt = now
        fa.running = false; running = false; tracking = true
        value = v
        progress = p
    }
    // Let go with velocity `v` (fractions of the travel per second; the hand's when omitted): on to the nearer end (`b` or
    // `a`, projected 100 ms on) on the curve, keeping the velocity; `landed(at)` says which. `to` stays the owner's.
    function release(v) {
        if (!tracking) return
        var span = tb - ta
        var pv = v === undefined ? velocity / span : v
        velocity = pv * span
        var end = (value - ta) / span + pv * 0.1 >= 0.5 ? tb : ta
        tracking = false
        running = true   // (a release is a retarget mid-flight: go() keeps the velocity)
        go(end)
    }

    property FrameAnimation fa: FrameAnimation {
        running: false
        onTriggered: d.advance(frameTime)
    }
}
