import QtQuick
import "../../../core"

// dissolve (W59.8b, K83; docs/ux/motion-engine.md §5 — paper burning: souls, hallownest, ember): the card burns away from the
// module it came from. The fire runs out over the paper in a ragged front (value noise, biased by the distance from where it
// starts), its edge a 2-px glow of the ember, the char behind it fading to nothing. Closing burns the card away; opening runs
// the same front back, so the card condenses out of the embers. At p = 1 the front is past the card: the card itself.
// Params (`motion.form_params.dissolve`): edge, the role of the glow: "accent" (the default), "ember" (the palette's tertiary),
// "warning" or "text". The char is the ink on a light card and a darker shade of the card on a dark one. The pass is
// dissolve.frag.
SheetForm {
    id: dis

    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    readonly property string role: params && params.edge ? params.edge : "accent"
    readonly property color ember: role === "ember" ? Theme.tertiary : role === "warning" ? Theme.warning
        : role === "text" ? Theme.fg : Theme.accent
    readonly property color charInk: lum(Theme.fg) < lum(Theme.surface) ? Theme.fg : Qt.darker(Theme.surface, 2.4)
    // Where the fire starts: the origin's middle along the hinge, on the hinge (the bar's edge of the card).
    readonly property point seed: Qt.point(hinge.x + originA * axisA.x, hinge.y + originA * axisA.y)

    SheetForm.Pass {
        host: dis
        name: "dissolve"
        u0: Qt.vector4d(dis.seed.x, dis.seed.y, 0, 2)
        u1: Qt.vector4d(dis.ember.r, dis.ember.g, dis.ember.b, 0)
        u2: Qt.vector4d(dis.charInk.r, dis.charInk.g, dis.charInk.b, 0)
        u3: Qt.vector4d(Math.max(1, dis.capture.textureSize.width), Math.max(1, dis.capture.textureSize.height),
            0.5, 0.4)
    }
}
