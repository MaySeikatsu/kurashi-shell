import QtQuick
import "../../core"
import "../../core/motion/curves.js" as C

// Accents (K83, docs/ux/motion-engine.md §3): a surface's secondary motion as one area-preserving Scale (sx · sy = 1) —
//   squash  while it moves fast it narrows along its travel and lands with a bulge: `squash` × the velocity against the
//           travel (MorphSprings' rule for the morphs; lively 0.06);
//   jelly   after it lands open it wobbles home on a short spring (pudding): sx = 1 + a·s(t), sy = 1 / sx, a = 8 % ×
//           `jelly`, the spring K83's `spring(260, 0.7)`.
// Put `scale` in the surface's `transform` and feed the motion it accents (a Driver's `velocity`, `progress`, `running`
// and its travel's size). Nothing runs unless a jelly wobbles (one FrameAnimation, only then: Ma); with both accents
// 0 (every profile today but lively's squash) the Scale stays identity.
QtObject {
    id: ac
    property real squash: Theme.motionAccent("squash")
    property real jelly: Theme.motionAccent("jelly")
    property bool enabled: true
    // The motion: velocity (units/s), the travel's size (units), progress (1 = in place) and whether it moves.
    property real velocity: 0
    property real span: 1
    property real progress: 1
    property bool moving: false
    // The reference speed's floor (units/s): MorphSprings uses 600 px/s so a short travel does not squash hard.
    property real minSpeed: 0
    // The item the Scale is about, and its fixed edge ("" = its centre; "top" … the hinge stays put).
    property Item target: null
    property string edge: ""
    // Along the travel: the axis that squashes and stretches ("y" for a top/bottom edge, "x" for a side).
    readonly property bool alongX: edge === "left" || edge === "right"

    readonly property real squeeze: enabled && squash > 0
        ? squash * Math.max(-1, Math.min(1, velocity / Math.max(minSpeed, Math.abs(span) * 5, 1e-6))) : 0
    property real wobble: 0
    // Along the travel it stretches (1 + wobble), across it narrows (1 − squeeze): one factor, its inverse on the other
    // axis, so the area stays.
    readonly property real along: (1 + squeeze) * (1 + wobble)
    readonly property real sx: alongX ? along : 1 / along
    readonly property real sy: alongX ? 1 / along : along
    readonly property Scale scale: Scale {
        origin.x: !ac.target ? 0 : ac.edge === "left" ? 0 : ac.edge === "right" ? ac.target.width : ac.target.width / 2
        origin.y: !ac.target ? 0 : ac.edge === "top" ? 0 : ac.edge === "bottom" ? ac.target.height : ac.target.height / 2
        xScale: ac.sx
        yScale: ac.sy
    }

    readonly property var spring: C.prepare({ kind: "spring", ms: 260, response: 260, bounce: 0.7 })
    property real t: 0
    property real v0: 0
    property var out: ({ d: 0, v: 0 })
    onMovingChanged: if (!moving && progress >= 0.999) kick()
    // Start the wobble (also for a surface that lands by other means).
    function kick() {
        if (!enabled || jelly <= 0) return
        var wd = spring.w0 * Math.sqrt(Math.max(0, 1 - spring.zeta * spring.zeta))
        v0 = 0.08 * Math.min(1, jelly) * wd
        t = 0
        fa.running = true
    }
    property FrameAnimation fa: FrameAnimation {
        running: false
        onTriggered: {
            ac.t += Math.min(frameTime, 0.05) * 1000
            C.springEval(ac.spring, 0, ac.v0, ac.t, ac.out)
            if (ac.t > 120 && Math.abs(ac.out.d) < 1e-4 && Math.abs(ac.out.v) < 1e-2) { ac.wobble = 0; running = false }
            else ac.wobble = ac.out.d
        }
    }
}
