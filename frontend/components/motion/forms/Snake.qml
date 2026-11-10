import QtQuick
import "../../../core"

// snake (I467, K114; docs/ux/motion-engine.md §5 — the snake game): the card is a grid of cells and the snake draws it:
// along the first row from the side the card came from, down one, back along the next, and so on away from the bar. The
// head is one cell in the head's colour, the cells behind it are its body (the ink, inset so they read as segments), and
// behind its tail the cells are the card. Stepped on purpose: the head moves a cell at a time. At p = 1 the snake has left
// the last cell: the card itself. Closing, it eats the card the same way back.
// Params (`motion.form_params.snake`): cell (px, default by the card's size), length (cells, default 5), ink: "accent"
// (the default), "secondary", "tertiary" or "text". The head is the text's colour. The pass is snake.frag.
SheetForm {
    id: sn

    readonly property string role: params && params.ink ? params.ink : "accent"
    readonly property color ink: role === "secondary" ? Theme.secondary : role === "tertiary" ? Theme.tertiary
        : role === "text" ? Theme.fg : Theme.accent
    readonly property color headInk: role === "text" ? Theme.accent : Theme.fg
    readonly property real cell: params && params.cell > 0 ? Math.max(6, Math.min(96, params.cell))
        : Math.max(14, Math.min(44, Math.sqrt(along * away / 150)))
    readonly property real len: params && params.length > 0 ? Math.max(1, Math.min(40, params.length)) : 5

    SheetForm.Pass {
        host: sn
        name: "snake"
        u0: Qt.vector4d(sn.cell, sn.len, sn.originA > sn.along / 2 ? 1 : 0, 0)
        u1: Qt.vector4d(sn.ink.r, sn.ink.g, sn.ink.b, 0)
        u2: Qt.vector4d(sn.headInk.r, sn.headInk.g, sn.headInk.b, 0)
        u3: Qt.vector4d(sn.edge === "bottom" || sn.edge === "right" ? 1 : 0, sn.horizontal ? 1 : 0, 0, 0)
    }
}
