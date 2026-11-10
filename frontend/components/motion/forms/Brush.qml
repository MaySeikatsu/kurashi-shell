import QtQuick
import "../../../core"

// brush (I467, K114; docs/ux/motion-engine.md §5 — a brush painting the surface in): strokes laid one after another away
// from the bar, forth, then back, slightly diagonal, each a little over the last; their edges ragged with bristle streaks,
// the head running dry ahead of the paint. Fresh paint is the ink and turns into the card as the brush moves on. At p = 1
// the last stroke is past the card: the card itself. Closing wipes it away the same way back.
// Params (`motion.form_params.brush`): strokes (2 … 12, default by the card's depth), slope (how many strokes a stroke
// rises over the card, default 0.6), ink: "accent" (the default), "secondary", "tertiary" or "text". The pass is brush.frag.
SheetForm {
    id: br

    readonly property string role: params && params.ink ? params.ink : "accent"
    readonly property color ink: role === "secondary" ? Theme.secondary : role === "tertiary" ? Theme.tertiary
        : role === "text" ? Theme.fg : Theme.accent
    readonly property real strokes: params && params.strokes > 0 ? Math.max(2, Math.min(12, params.strokes))
        : Math.max(3, Math.min(9, Math.round(away / 80)))
    readonly property real slope: params && params.slope !== undefined ? Math.max(-2, Math.min(2, params.slope)) : 0.6

    SheetForm.Pass {
        host: br
        name: "brush"
        u0: Qt.vector4d(br.strokes, br.slope, Math.max(12, Math.min(40, br.along / 14)), 0)
        u1: Qt.vector4d(br.ink.r, br.ink.g, br.ink.b, 0)
        u3: Qt.vector4d(br.edge === "bottom" || br.edge === "right" ? 1 : 0, br.horizontal ? 1 : 0, 0, 0)
    }
}
