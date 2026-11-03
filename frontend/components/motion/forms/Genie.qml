import QtQuick

// genie (W59.5, K83; docs/ux/motion-engine.md §5 — the user's magic lamp; aqua's dock and toasts, D4): the card pours
// into the module it came from in macOS's two phases. Closing, first the sides bend: the rows by the hinge narrow to the
// module's width and swing over its centre, the far rows stay as they are, an S-curve between (the funnel). Then the
// body slides through the funnel's mouth into the module, each row taking the funnel's width where it is, and fades as
// it goes in. Opening is the same travel backwards: the card pours out of the lamp, then its sides relax.
// The funnel is exact: the vertex pass moves a row-strip mesh (it only needs to cover the silhouette), the fragment pass
// finds every pixel's place on the card analytically, so the curved sides are smooth, anti-aliased and the content is
// mapped without the trapezoid kink of a mesh warp. Flat (p = 1) is the card itself.
// Origin (brief §7): the pressed module's rect (a dock icon, a bar module, the pill); without one the lamp is a 32-px
// mouth at the hinge's middle (§10, "origin gone").
// Params (`motion.form_params.genie`): bend 0–1 (0.5) — how much of the card the funnel takes: 0 a long, gentle neck
// over the whole card, 1 a short, sharp one by the hinge.
SheetForm {
    id: genie

    readonly property real bend: params && params.bend !== undefined ? Math.max(0, Math.min(1, params.bend)) : 0.5

    // The origin in the hinge frame (a along the hinge, d away from it: < 0 lies beyond the hinge, in the bar).
    function canon(x, y) {
        var rx = x - area.x - hinge.x, ry = y - area.y - hinge.y
        return Qt.point(rx * axisA.x + ry * axisA.y, rx * axisD.x + ry * axisD.y)
    }
    readonly property bool hasOrigin: origin.width > 0 || origin.height > 0
    readonly property var lamp: {
        if (!hasOrigin) return { c: along / 2, w: Math.min(along, 32), depth: 0 }
        var p0 = canon(origin.x, origin.y), p1 = canon(origin.x + origin.width, origin.y + origin.height)
        var a0 = Math.min(p0.x, p1.x), a1 = Math.max(p0.x, p1.x)
        var d0 = Math.min(p0.y, p1.y)
        var c = Math.max(0, Math.min(along, (a0 + a1) / 2))
        // (a module wider than the card pours nothing: it would only slide)
        var w = Math.max(12, Math.min(along, a1 - a0))
        return { c: c, w: w, depth: Math.max(0, Math.min(96, -d0)) }
    }
    // How deep the body goes into the module before it is gone: half the module's depth (its middle), at least 6 px.
    readonly property real fadeLen: Math.max(6, lamp.depth / 2)
    // The funnel's length (screen px from the mouth to where a row has its full width again).
    readonly property real funnel: Math.max(24, away * (1 - 0.55 * bend))

    // The two phases on p (closing reads it from 1 down; opening is the same curve backwards): the bend over the first
    // 55 % of a close, the slide from 40 % — they overlap, so the body is already moving while the sides finish.
    readonly property real q: 1 - p
    readonly property real bent: ease(sub(q, 0, 0.55))
    readonly property real slid: ease(sub(q, 0.4, 1))
    // The slide's length: the far edge ends `fadeLen` inside the module.
    readonly property real travel: away + fadeLen

    // A row strip per ~6 px (the funnel's curve between two rows is far under a pixel), a few columns across.
    readonly property int rows: Math.max(32, Math.min(160, Math.ceil(away / 6)))

    SheetForm.Pass {
        host: genie
        name: "genie"
        mesh: GridMesh { resolution: genie.horizontal ? Qt.size(genie.rows, 4) : Qt.size(4, genie.rows) }
        u0: Qt.vector4d(genie.bent, genie.slid * genie.travel, genie.fadeLen, genie.funnel)
        u1: Qt.vector4d(genie.lamp.c, genie.lamp.w, genie.shade / 0.35, 0)
    }
}
