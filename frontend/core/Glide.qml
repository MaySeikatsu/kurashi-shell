import QtQuick
import "motion"

// One value that moves to `to` the way the motion profile says (K74, K83; docs/ux/motion.md, motion-engine.md §9): a
// Driver on the profile's curves (`Theme.motionCurves`) — on the open curve when it moves the opening way (`openUp`: a
// rising value opens), on the close curve back, a new target mid-way starting from where it is — on K42's spring while
// it springs (calm, lively: `spring`/`damping`, as the SpringAnimation each surface had before), or at once with motion
// off. `value` is the output. Nothing runs while it rests (Ma).
Driver {
    id: gl
    curves: Theme.motionCurves
    // Spring mode: the constants a surface had on its SpringAnimation.
    spring: Theme.spring
    damping: Theme.damping
    // Today's glide: a new target starts the curve as written (the velocity is not carried into it).
    keepVelocity: false
    readonly property bool timed: enabled && (kindOf("open") === "cubic" || kindOf("open") === "steps"
        || kindOf("open") === "linear")
    readonly property bool springs: enabled && kindOf("open").indexOf("spring") === 0
    function kindOf(r) { var c = Theme.motionCurve(r); return c && c.kind ? c.kind : "none" }
    // A profile switch mid-way lands at once (as the old timed animation did).
    onTimedChanged: snap(to)
}
