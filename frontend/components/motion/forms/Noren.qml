import QtQuick

// noren (W59.8, K83; docs/ux/motion-engine.md §5 — the shop curtain): the card arrives as strips hanging from its hinge on
// the bar. Each strip drops in from behind the bar, on its own share of the progress (outward from the origin, a lag per
// strip), and sways like a damped pendulum (at most 4°, a shear about the bar, so its top stays on the hinge). The strips
// part as they swing, so slits open between them mid-way; at rest they are the card, closed, and the sway has settled
// exactly at p = 1 (noren.vert). One pass per strip: a shared mesh would share the vertex column between two strips, and
// the slit could not open. Pass order is draw order: a later strip hangs over the one before it.
// Params (`motion.form_params.noren`): strips 3–7 (0 = auto: one per ~130 px along the hinge).
SheetForm {
    id: noren

    readonly property int strips: {
        var n = params && params.strips > 0 ? Math.round(params.strips) : Math.round(along / 130)
        return Math.max(3, Math.min(7, n))
    }
    readonly property real stripW: along / strips
    // The lag per strip, outward from the origin (noren.vert): the last strip still has its whole drop in the progress left
    // after the lags, so every strip lands at 1 (the same rule as fan's, with its own step).
    readonly property real lag: Math.min(0.08, 0.55 / strips)
    // The sway's amplitude: 3.6 degrees (its peak is under four), in radians.
    readonly property real swing: 3.6 * Math.PI / 180

    Repeater {
        model: noren.strips
        delegate: SheetForm.Pass {
            required property int index
            host: noren
            name: "noren"
            // The strip's own rectangle: a column of the card along a top or bottom bar, a row along a side bar.
            x: host.area.x + (host.horizontal ? 0 : index * host.stripW)
            y: host.area.y + (host.horizontal ? index * host.stripW : 0)
            width: host.horizontal ? host.area.width : host.stripW
            height: host.horizontal ? host.stripW : host.area.height
            mesh: GridMesh { resolution: Qt.size(1, 1) }
            // x the strips, y a strip's width (rest), z the pivot's place on the bar.
            u0: Qt.vector4d(noren.strips, noren.stripW, noren.originA, noren.along / 2)
            // x the lag per strip, y the sway's amplitude.
            u1: Qt.vector4d(noren.lag, noren.swing, 0, 0)
            // xy the strip's offset in the card, z its index.
            u3: Qt.vector4d(host.axisA.x * index * host.stripW, host.axisA.y * index * host.stripW, index, 0)
        }
    }
}
