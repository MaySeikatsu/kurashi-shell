import QtQuick

// roll (W59.4, K83; docs/ux/motion-engine.md §5 — the user's carpet): the card comes out rolled up from under the bar's
// edge and rolls away from the hinge, laying itself flat behind the roller; the roll's outside is the back of the paper
// (`backside`), it thins as it gives out paper, and its last turn lifts off as a short curl before it lies flat at rest.
// Close rolls it back up and under the bar. `scroll` (makimono, sumi's sidebars): two rollers from the middle outward —
// one toward the hinge, one away — the sheet between them widening.
// Params (`motion.form_params.roll`): radius 10–28 px (18), variant "roll" | "scroll".
SheetForm {
    id: roll

    readonly property real r0: Math.max(10, Math.min(28, params && params.radius > 0 ? params.radius : 18))
    readonly property bool scroll: params && params.variant === "scroll"
    // The far roller's contact line: from behind the bar (two radii above the hinge: nothing shows) to the far edge.
    // The scroll's rollers start back to back at the middle.
    readonly property real mid: away / 2
    readonly property real s1: scroll ? mid + r0 + p * (away - mid - r0) : -2.2 * r0 + p * (away + 2.2 * r0)
    readonly property real s0: scroll ? (mid - r0) * (1 - p) : 0
    // A roll is thinner the less paper it holds (r² grows with the paper wound on): from r0 to about half of it.
    readonly property real held: Math.max(0, Math.min(1, (away - Math.max(0, s1)) / Math.max(1, scroll ? away - mid : away)))
    readonly property real r: r0 * (0.55 + 0.45 * Math.sqrt(held))

    // The roller's contact shadow on what lies under the card (the paper ends at the roller: nothing of the sheet is
    // there to shade), from under its front edge outward; lighter as the roll thins.
    component Ground: Rectangle {
        // canonical band [d0, d1] (d0 at the roller, d1 away from it), across the whole hinge
        property real d0: 0
        property real d1: 0
        readonly property real lo: Math.max(0, Math.min(d0, d1))
        readonly property real hi: Math.max(0, Math.max(d0, d1))
        readonly property bool rising: (d1 > d0) === (roll.edge === "top" || roll.edge === "left")
        x: roll.area.x + (roll.horizontal ? (roll.edge === "left" ? lo : roll.area.width - hi) : 0)
        y: roll.area.y + (roll.horizontal ? 0 : (roll.edge === "top" ? lo : roll.area.height - hi))
        width: roll.horizontal ? hi - lo : roll.area.width
        height: roll.horizontal ? roll.area.height : hi - lo
        visible: hi - lo > 0.5
        gradient: Gradient {
            orientation: roll.horizontal ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, rising ? 0.2 * roll.groundK : 0) }
            GradientStop { position: 0.35; color: Qt.rgba(0, 0, 0, 0.09 * roll.groundK) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, rising ? 0 : 0.2 * roll.groundK) }
        }
    }
    readonly property real groundK: Math.sqrt(held) * (scroll ? smooth01(p / 0.08) : 1)
    Ground { d0: roll.s1 + roll.r * 0.6; d1: roll.s1 + roll.r * 2.4 }
    Ground { visible: roll.scroll && hi - lo > 0.5; d0: roll.s0 - roll.r * 0.6; d1: roll.s0 - roll.r * 2.4 }

    SheetForm.Pass {
        host: roll
        name: "roll"
        // (the makimono's two rolls appear together at the middle: they fade in over the first 8 %)
        opacity: roll.scroll ? roll.smooth01(roll.p / 0.08) : 1
        mesh: GridMesh {
            readonly property int rows: Math.max(24, Math.min(360, Math.ceil(roll.away / 3)))
            resolution: roll.horizontal ? Qt.size(rows, 2) : Qt.size(2, rows)
        }
        u0: Qt.vector4d(roll.s1, roll.r, roll.scroll ? 1 : 0, roll.s0)
    }
}
