import QtQuick
import "../../../core"

// fan (W59.8, K83; docs/ux/motion-engine.md §5 — sensu, the folding fan): the card opens like a Japanese folding fan about
// a pivot at the origin (the pressed module, behind the bar). Its ribs (the sticks) open in sequence, from the tips in (the
// outer ribs lead, so the fan never folds over itself); the paper between them, the leaves, stretches into fan sectors and
// pleats: alternate leaves tilt toward and away from the viewer, in alternate shades under the K82 light; the rib lines are
// thin, in the look's outline colour. The fan lands flat: at rest the card is the identity. Closing folds the ribs back to
// the pivot — the same map, run backwards.
// The geometry is fan.vert's, the shading and the lines fan.frag's (both from the same map, so they agree).
// Params (`motion.form_params.fan`): ribs 5–12 (0 = auto: one per ~70 px along the hinge).
SheetForm {
    id: fan

    readonly property int ribs: {
        var n = params && params.ribs > 0 ? Math.round(params.ribs) : Math.round(along / 70)
        return Math.max(5, Math.min(12, n))
    }
    // The leaves between the ribs (a rib is a fold line; the card's two edges are its silhouette).
    readonly property int leaves: ribs - 1
    readonly property real leafW: along / leaves
    // The lag per leaf (Fold's rule). The rib that starts last keeps 45 % of the travel with the pivot at an end of the bar
    // and 72 % with it in the middle (12 ribs).
    readonly property real lag: Math.min(0.06, 0.55 / Math.max(1, leaves))
    // The pivot's depth behind the bar, D0 / (1 − p)² (fan.vert): a fifth of the half-length at p = 0, so the sticks meet at
    // the bar and the outer ribs reach about 45° mid-way (the tips open from the outside in), then the fan lies flat
    // (3° at the rim at p = 0.9, 2 px at 0.97, under 1 px at 0.99).
    readonly property real pivotD0: along / 10
    // Rows along the leaves: the sectors' arcs stay round (a row every ~12 px).
    readonly property int rows: Math.max(16, Math.min(48, Math.round(away / 12)))
    readonly property color ink: Theme.frameOutlineColor
    // The eye over the pivot: the fan is seen from the module it opens from.
    eyeA: originA

    SheetForm.Pass {
        host: fan
        name: "fan"
        // The ribs fall on mesh columns, four per leaf, along the hinge: rows along it for a side bar (Fold's swap, so the
        // creases stay vertex lines on every edge).
        mesh: GridMesh { resolution: fan.horizontal ? Qt.size(fan.rows, fan.leaves * 4) : Qt.size(fan.leaves * 4, fan.rows) }
        // x the leaves, y a leaf's width (rest), z the pivot's place on the bar, w half the length along the bar.
        u0: Qt.vector4d(fan.leaves, fan.leafW, fan.originA, fan.along / 2)
        // x the pivot's depth at p = 0, y the lag per leaf, z the pleat's height (a fifth of a leaf), w the ramp (px).
        u1: Qt.vector4d(fan.pivotD0, fan.lag, 0.2 * fan.leafW, 60)
        // rgb the rib lines' colour, a their strength.
        u2: Qt.vector4d(fan.ink.r, fan.ink.g, fan.ink.b, 0.9)
    }
}
