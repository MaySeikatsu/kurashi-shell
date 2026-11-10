import QtQuick
import "../../../core"

// splat (I467, K114; docs/ux/motion-engine.md §5 — ink thrown at the surface, as Splatoon's): drops of ink land one after
// another, the first on the module the card came from, and spread with lobes and droplets; where ink has landed the card
// shows a moment later, so every drop is ink first and surface after. A last flood carries the ink past every corner: at
// p = 1 the card is whole. Closing runs it back: the card shrinks into drops of ink that go.
// Params (`motion.form_params.splat`): drops (3 … 12, default by the card's size), ink, the role of the ink: "accent" (the
// default), "secondary", "tertiary" or "text". The pass is splat.frag.
SheetForm {
    id: spl

    readonly property string role: params && params.ink ? params.ink : "accent"
    readonly property color ink: role === "secondary" ? Theme.secondary : role === "tertiary" ? Theme.tertiary
        : role === "text" ? Theme.fg : Theme.accent
    readonly property real drops: params && params.drops > 0 ? Math.max(3, Math.min(12, params.drops))
        : Math.max(5, Math.min(12, Math.round(along * away / 26000)))

    SheetForm.Pass {
        host: spl
        name: "splat"
        u0: Qt.vector4d(spl.originA, 0, spl.drops, 0)
        u1: Qt.vector4d(spl.ink.r, spl.ink.g, spl.ink.b, 0)
        u3: Qt.vector4d(spl.edge === "bottom" || spl.edge === "right" ? 1 : 0, spl.horizontal ? 1 : 0, 0, 0)
    }
}
