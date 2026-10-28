import QtQuick

// One value that moves to `to` the way the motion profile says (K74, docs/ux/motion.md): on Caelestia's curves while the
// motion is timed (expressive) — `openCurve` over `openMs` when it moves the opening way (`openUp`: a rising value opens),
// `closeCurve` over `closeMs` back, a new target mid-way starting from where it is — on a spring while it springs (calm,
// lively: `spring`/`damping`, as the SpringAnimation each surface had before), or at once with motion off. `value` is
// the output. Nothing runs while it rests (Ma).
QtObject {
    id: gl
    property real to: 0
    property bool openUp: true
    // Spring mode: the constants a surface had on its SpringAnimation.
    property real spring: Theme.spring
    property real damping: Theme.damping
    property real epsilon: 0.01
    // Off: cut (reduced motion, the surface's own reasons).
    property bool enabled: true
    readonly property bool timed: Theme.timed && enabled
    readonly property bool springs: Theme.springOn && !Theme.timed && enabled
    // The spring's value, the timed value, and the one in effect (plain values: a binding to `to` would jump first).
    property real sv: 0
    property real tv: 0
    Component.onCompleted: { sv = to; tv = to }
    readonly property real value: timed ? tv : sv
    readonly property bool running: anim.running || sprung.running

    property NumberAnimation anim: NumberAnimation {
        target: gl
        property: "tv"
        easing.type: Easing.BezierSpline
    }
    property SpringAnimation sprung: SpringAnimation {
        target: gl
        property: "sv"
        spring: gl.spring
        damping: gl.damping
        epsilon: gl.epsilon
    }
    onToChanged: go()
    onTimedChanged: { anim.stop(); sprung.stop(); sv = to; tv = to }
    function go() {
        if (timed) {
            sprung.stop(); sv = to
            if (Math.abs(to - tv) < 1e-4) { anim.stop(); tv = to; return }
            var opening = (to > tv) === openUp
            anim.stop()
            anim.from = tv
            anim.to = to
            anim.duration = Math.max(1, opening ? Theme.openMs : Theme.closeMs)
            anim.easing.bezierCurve = opening ? Theme.openCurve : Theme.closeCurve
            anim.start()
        } else if (springs) {
            anim.stop(); tv = to
            sprung.to = to
            if (!sprung.running) sprung.start()
        } else {
            anim.stop(); sprung.stop(); sv = to; tv = to
        }
    }
    // Set without motion (a surface made at rest).
    function snap(v) { anim.stop(); sprung.stop(); to = v; sv = v; tv = v }
}
