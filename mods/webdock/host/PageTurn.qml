import QtQuick
import "components/motion/forms"

// The notebook's page turn (W69; docs/ux/webdock.md "Page styles" › Motion): the motion engine's `book` sheet (K83,
// W59.4: frontend/components/motion/forms/Book.qml and shaders/motion/book.*) run as one page turning about the coil.
// Book's own spines split the card through its middle (a book or a pad opening); here the spine is the sheet's bound
// edge itself (`u1.x = 0` on the hinge, along it: `u0.w = 1`) and the whole sheet is the page that moves, so only the
// moving pass is drawn. The sheet is captured alone (`source`: the sheet with the header and the page on it); the cover
// and the coil stay where they are. progress 0: the sheet stands on edge over the binding (seen edge-on, nothing
// shows), 1: it lies flat — the frame at rest. Loaded by the card only while the sheet turns (Ma: no layer at rest).
SheetForm {
    id: turn
    // (named as FormHost names its forms: the layer's up and released lines say "webdock book")
    surface: "webdock"
    form: "book"
    // The eye further off than the shell's sheets have it (they turn half a card; this turns a whole one, up to the
    // large size): a standing page grows by a fifth, not by half.
    focal: Math.max(1400, away * 6)

    // The page's angle at the binding (π/2 standing, 0 flat) and its free edge's lag, as the book's cover has them.
    readonly property real t: ease(p)
    readonly property real psi: Math.PI / 2 * (1 - t)
    readonly property real curl: 0.5 * Math.sin(Math.PI * t)

    SheetForm.Pass {
        host: turn
        name: "book"
        // The page bends across the binding: the grid is fine along `d`.
        mesh: GridMesh { resolution: turn.horizontal ? Qt.size(48, 1) : Qt.size(1, 48) }
        u0: Qt.vector4d(0, turn.psi, turn.curl, 1)
        u1: Qt.vector4d(0, 1, 1, turn.away)
    }
}
