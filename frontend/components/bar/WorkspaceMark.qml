import QtQuick
import QtQuick.Shapes
import "../../core"

// The focused workspace's mark as one travelling shape (session 32, the user: "animate the bar symbol fluently … it
// morphs over to the other workspace … with a little wobble if the motion profile has that"; docs/ux/workspace-motion.md).
// The row's keys stay where they are; this mark lies over them and moves from the old key to the new one:
//   slide   — both ends move together, the pill glides over;
//   stretch — the end in the direction of travel runs ahead, the other catches up (a worm);
//   goo     — stretch, and the middle thins to a neck while it is drawn out, so it reads as liquid: two bulbs, one
//             flowing into the other.
// The wobble is the motion profile's own: on springs (`motion.kind = spring`) the ends spring with `motion.spring.*`
// (a low damping overshoots and settles); timed motion uses its duration and `motion.spring.overshoot`; motion off snaps.
// Ma: nothing runs at rest — the ends animate only when the focused key moves (Behaviors), and the shape repaints only
// then.
Item {
    id: mk
    // The focused key's box in the parent's coordinates (the target), and the mark's colour.
    property real goalX: 0
    property real goalW: 0
    property real goalY: 0
    property real goalH: 0
    property color color: Theme.accent
    property string style: "goo"
    // False while the module is out of sight or the first target is not known yet: the ends jump (no travel at load).
    property bool live: true

    readonly property string kind: !Theme.springOn ? "none" : Theme.motionKind
    readonly property bool moves: live && style !== "off" && kind !== "none"
    readonly property bool springs: kind === "spring"

    // The direction of the last move: +1 to the right, -1 to the left (which end leads).
    property int dir: 1
    // The ends, animated.
    property real x0: goalX
    property real x1: goalX + goalW
    property real yTop: goalY
    property real hNow: goalH

    // Which end leads, and how much faster: slide moves both alike.
    readonly property bool split: style === "stretch" || style === "goo"
    readonly property real leadSpring: Theme.spring * (split ? 1.6 : 1)
    readonly property real trailSpring: Theme.spring * (split ? 0.45 : 1)
    readonly property int leadMs: Math.round(Theme.stdMs * (split ? 0.7 : 1))
    readonly property int trailMs: Math.round(Theme.stdMs * (split ? 1.8 : 1))

    onGoalXChanged: if (goalX + goalW / 2 !== (x0 + x1) / 2) dir = goalX + goalW / 2 > (x0 + x1) / 2 ? 1 : -1

    Behavior on x0 {
        enabled: mk.moves
        animation: mk.springs ? x0Spring : x0Timed
    }
    Behavior on x1 {
        enabled: mk.moves
        animation: mk.springs ? x1Spring : x1Timed
    }
    SpringAnimation {
        id: x0Spring
        spring: mk.dir < 0 ? mk.leadSpring : mk.trailSpring
        damping: Theme.damping
        epsilon: 0.25
    }
    SpringAnimation {
        id: x1Spring
        spring: mk.dir > 0 ? mk.leadSpring : mk.trailSpring
        damping: Theme.damping
        epsilon: 0.25
    }
    NumberAnimation {
        id: x0Timed
        duration: mk.dir < 0 ? mk.leadMs : mk.trailMs
        easing.type: Theme.overshoot > 0 ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: Theme.overshoot
    }
    NumberAnimation {
        id: x1Timed
        duration: mk.dir > 0 ? mk.leadMs : mk.trailMs
        easing.type: Theme.overshoot > 0 ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: Theme.overshoot
    }

    // How far the mark is drawn out past its key's width, 0 at rest … 1 stretched over about two keys.
    readonly property real span: Math.max(0, x1 - x0)
    readonly property real stretch: goalW > 0 ? Math.max(0, Math.min(1, (span - goalW) / (goalW * 1.1))) : 0
    // Goo: the neck's depth from each edge (at most a third of the height each side, so it never breaks in two).
    readonly property real neck: style === "goo" ? stretch * hNow * 0.36 : 0

    // How much of a box [x, x + w] the mark covers now, 0..1 (the keys' numbers turn to the ink on the mark by it).
    function cover(x, w) {
        if (w <= 0 || style === "off") return 0
        var a = Math.max(x, x0), b = Math.min(x + w, x1)
        return Math.max(0, Math.min(1, (b - a) / w))
    }

    visible: style !== "off" && goalW > 0
    Shape {
        id: shape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // (a still mark is one capsule: the neck and the bulbs come only while it travels)
        readonly property real r: Math.min(mk.hNow / 2, mk.span / 2)
        readonly property real l: mk.x0
        readonly property real rt: Math.max(mk.x1, mk.x0 + 0.5)
        readonly property real t: mk.yTop
        readonly property real b: mk.yTop + mk.hNow
        readonly property real mid: (l + rt) / 2
        readonly property real d: mk.neck
        // the straight run between the caps, halved: where the bulbs bend into the neck
        readonly property real half: Math.max(0, (rt - l) / 2 - r)
        ShapePath {
            fillColor: mk.color
            strokeWidth: -1
            startX: shape.l + shape.r
            startY: shape.t
            // top: left bulb → neck → right bulb
            PathCubic {
                x: shape.mid; y: shape.t + shape.d
                control1X: shape.l + shape.r + shape.half * 0.55; control1Y: shape.t
                control2X: shape.mid - shape.half * 0.45; control2Y: shape.t + shape.d
            }
            PathCubic {
                x: shape.rt - shape.r; y: shape.t
                control1X: shape.mid + shape.half * 0.45; control1Y: shape.t + shape.d
                control2X: shape.rt - shape.r - shape.half * 0.55; control2Y: shape.t
            }
            PathArc {
                x: shape.rt - shape.r; y: shape.b
                radiusX: shape.r; radiusY: shape.hNowHalf
                useLargeArc: false
                direction: PathArc.Clockwise
            }
            // bottom: right bulb → neck → left bulb
            PathCubic {
                x: shape.mid; y: shape.b - shape.d
                control1X: shape.rt - shape.r - shape.half * 0.55; control1Y: shape.b
                control2X: shape.mid + shape.half * 0.45; control2Y: shape.b - shape.d
            }
            PathCubic {
                x: shape.l + shape.r; y: shape.b
                control1X: shape.mid - shape.half * 0.45; control1Y: shape.b - shape.d
                control2X: shape.l + shape.r + shape.half * 0.55; control2Y: shape.b
            }
            PathArc {
                x: shape.l + shape.r; y: shape.t
                radiusX: shape.r; radiusY: shape.hNowHalf
                useLargeArc: false
                direction: PathArc.Clockwise
            }
        }
        readonly property real hNowHalf: mk.hNow / 2
    }
}
