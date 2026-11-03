import QtQuick
import QtTest
import ".."

// Driver (W59.2): runs only while moving, lands exactly, keeps spring velocity through a retarget, cuts on `none`,
// tracks and releases. Needs Quickshell's QML module on the import path (test-motion.sh passes it); offscreen.
TestCase {
    name: "driver"
    when: windowShown
    readonly property var cubic: ({ kind: "cubic", ms: 200, points: [0.38, 1.21, 0.22, 1, 1, 1] })
    readonly property var springQ: ({ kind: "spring_q", ms: 0, spring: 4.0, damping: 0.45 })
    readonly property var spring: ({ kind: "spring", ms: 300, response: 300, bounce: 0.3 })
    Component { id: dc; Driver {} }

    function make(c) { return dc.createObject(null, { curve: c, to: 0 }) }

    function test_rest_runs_nothing() {
        var d = make(cubic)
        verify(!d.running)
        compare(d.value, 0)
        d.destroy()
    }
    function test_cubic_lands_and_stops() {
        var d = make(cubic)
        d.to = 100
        verify(d.running)
        compare(d.progress, 0)
        var peak = 0
        for (var i = 0; i < 40 && d.running; i++) { wait(16); peak = Math.max(peak, d.value) }
        verify(!d.running, "still running")
        compare(d.value, 100)
        compare(d.progress, 1)
        verify(peak > 100, "expressive overshoots: " + peak)
        d.destroy()
    }
    function test_none_cuts() {
        var d = make({ kind: "none" })
        d.to = 5
        verify(!d.running)
        compare(d.value, 5)
        d.destroy()
    }
    function test_disabled_cuts() {
        var d = make(cubic)
        d.enabled = false
        d.to = 7
        verify(!d.running)
        compare(d.value, 7)
        d.destroy()
    }
    function test_spring_q_keeps_velocity_on_retarget() {
        var d = make(springQ)
        d.to = 1
        wait(120)
        verify(d.running)
        var v = d.velocity
        verify(v > 0)
        d.to = 0
        // the reversal starts from where it is with the velocity it had (still rising for a moment)
        compare(d.st.v, v)
        tryVerify(function () { return !d.running }, 4000)
        compare(d.value, 0)
        d.destroy()
    }
    function test_spring_closed_form_lands() {
        var d = make(spring)
        d.to = 10
        tryVerify(function () { return !d.running }, 4000)
        compare(d.value, 10)
        d.destroy()
    }
    function test_cubic_retarget_matches_velocity() {
        var d = make(cubic)
        d.to = 100
        wait(60)
        var v = d.velocity
        verify(v > 0)
        d.to = 200
        // the new curve starts with the slope the value had
        var s = d.active.segs[0]
        var slope0 = s.c1y / s.c1x
        verify(Math.abs(slope0 * (200 - d.from) * 1000 / d.active.ms - v) < 1e-6 * Math.max(1, v)
            || s.c1y === 2 || s.c1y === -1, "slope " + slope0 + " v " + v)
        tryVerify(function () { return !d.running }, 2000)
        compare(d.value, 200)
        d.destroy()
    }
    function test_track_and_release() {
        var d = make(cubic)
        d.to = 1
        tryVerify(function () { return !d.running }, 2000)
        d.track(0.3)
        verify(d.tracking)
        compare(d.value, 0.3)
        d.to = 0.5          // the owner's target does not move a tracked value
        compare(d.value, 0.3)
        d.track(0.8)
        var landed = -1
        d.landed.connect(function (at) { landed = at })
        d.release(0)
        verify(!d.tracking)
        tryVerify(function () { return !d.running }, 2000)
        compare(landed, 1)
        compare(d.value, 1)
        d.destroy()
    }
}
