import QtQuick

// fold (W59.4, K83; docs/ux/motion-engine.md §5 — the user's origami, Kami's default): the card folded accordion-wise
// into panels that hang from its hinge on the bar, each opening on its own sub-progress a little after the one before
// (the lag a hand gives it). With two axes it is a letter: first the small square under the origin swings down out of
// the bar, then it unfolds across into a strip, then the strip unfolds along, panel after panel. Close is the same
// travel backwards. The panels zig-zag (every other one toward the viewer), stay within ±90° of the screen and so never
// lie over one another; edge-on at p = 0 they draw nothing.
// Params (`motion.form_params.fold`): panels 2–5 (0 = auto: one per ~120 px away from the hinge), axes 1 · 2, crease
// 0–1 (the shading's strength, 0.35).
SheetForm {
    id: fold

    readonly property int axes: params && params.axes === 2 ? 2 : 1
    shade: params && params.crease !== undefined ? Math.max(0, Math.min(1, params.crease)) : 0.35
    // Along: one panel per ~120 px away from the hinge. Across (two axes): panels about as wide as the along ones are
    // tall, so the first thing out is a small square.
    readonly property int nd: {
        var n = params && params.panels > 0 ? params.panels : Math.round(away / 120)
        return Math.max(2, Math.min(5, n))
    }
    readonly property int na: axes === 2
        ? Math.max(2, Math.min(5, Math.round(along / Math.max(away / nd, 120)))) : 1
    // The across panel that stays: the one under the origin.
    readonly property int j0: na > 1 ? Math.max(0, Math.min(na - 1, Math.floor(originA / (along / na)))) : 0
    // The eye over the panel that stays: the folded flaps beside it are seen edge-on, as a thin edge, not a slab.
    eyeA: na > 1 ? (j0 + 0.5) * along / na : along / 2

    // Each panel's sub-progress: one axis — a lag of 0.12 between panels (less with many, so the last still has
    // 45 % of the travel); two axes — the square swings down (0–0.32), the strip opens across (0.18–0.56, the far
    // panels a little later), then along (from 0.4, lagged).
    readonly property var steps: {
        var p = fold.p, al = [], ac = []
        var half = Math.PI / 2
        if (axes === 1) {
            var lag = Math.min(0.12, 0.55 / Math.max(1, nd - 1))
            var dur = 1 - (nd - 1) * lag
            for (var k = 0; k < nd; k++)
                al.push((k % 2 ? -1 : 1) * half * (1 - ease(sub(p, k * lag, k * lag + dur))))
        } else {
            al.push(half * (1 - ease(sub(p, 0, 0.32))))
            var start = 0.4
            var lag2 = nd > 2 ? Math.min(0.12, 0.25 / (nd - 2)) : 0
            var dur2 = 1 - start - (nd - 2) * lag2
            for (k = 1; k < nd; k++) {
                var t0 = start + (k - 1) * lag2
                al.push((k % 2 ? -1 : 1) * half * (1 - ease(sub(p, t0, t0 + dur2))))
            }
            for (var j = 0; j < na; j++) {
                var r = Math.abs(j - j0)
                if (r === 0) { ac.push(0); continue }
                var a0 = 0.18 + 0.06 * (r - 1)
                ac.push((r % 2 ? 1 : -1) * half * (1 - ease(sub(p, a0, a0 + 0.32))))
            }
        }
        while (al.length < 5) al.push(0)
        while (ac.length < 5) ac.push(0)
        return { along: al, across: ac }
    }

    SheetForm.Pass {
        host: fold
        name: "fold"
        // The panel grid itself: every crease on a vertex line, each cell planar (perspective-correct through w).
        mesh: GridMesh { resolution: fold.horizontal ? Qt.size(fold.nd, fold.na) : Qt.size(fold.na, fold.nd) }
        u0: Qt.vector4d(fold.steps.along[0], fold.steps.along[1], fold.steps.along[2], fold.steps.along[3])
        u1: Qt.vector4d(fold.steps.along[4], fold.nd, fold.na, fold.j0)
        u2: Qt.vector4d(fold.steps.across[0], fold.steps.across[1], fold.steps.across[2], fold.steps.across[3])
        u3: Qt.vector4d(fold.steps.across[4], fold.shade / 0.35, 0, 0)
    }
}
