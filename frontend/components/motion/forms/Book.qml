import QtQuick

// book (W59.4, K83; docs/ux/motion-engine.md §5 — the user's notebook): closed, the card is one half of itself with the
// cover up (`cover`: the paper's back with the accent in it). It swings down out of the bar (0–0.34), then the cover
// opens about the spine (from 0.2), its free edge trailing in a slight curl that settles as it lands flat. The half under
// the origin stays; without an origin the right half (a book bound on the right, as Japanese books are). Close: the cover
// shuts and the closed book swings back up into the bar.
// Params (`motion.form_params.book`): spine "auto" | "centre" (perpendicular to the bar through the middle; auto) |
// "hinge" (along the bar through the middle of the card: a pad bound at the top).
SheetForm {
    id: book

    readonly property bool padSpine: params && params.spine === "hinge"
    // The spine's place, and which side of it moves: the far half for a pad; for a book the half away from the origin.
    readonly property real spinePos: padSpine ? away / 2 : along / 2
    readonly property bool hasOrigin: origin.width > 0 || origin.height > 0
    readonly property real side: padSpine ? 1 : (hasOrigin && originA < along / 2 ? 1 : -1)
    readonly property real half: padSpine ? away / 2 : along / 2
    eyeA: along / 2

    readonly property real swing: Math.PI / 2 * (1 - ease(sub(p, 0, 0.34)))
    readonly property real turn: ease(sub(p, 0.2, 1))
    readonly property real psi: Math.PI * (1 - turn)
    readonly property real curl: 0.55 * Math.sin(Math.PI * turn)

    // The half that stays, then the half that moves (drawn after: it lies over the other).
    Repeater {
        model: 2
        SheetForm.Pass {
            required property int index
            host: book
            name: "book"
            // planar along the spine; the moving page bends across it (and its half of the grid is the one used)
            mesh: GridMesh {
                readonly property int n: index === 1 ? 48 : 2
                resolution: (book.horizontal !== book.padSpine) ? Qt.size(1, n) : Qt.size(n, 1)
            }
            u0: Qt.vector4d(book.swing, book.psi, book.curl, book.padSpine ? 1 : 0)
            u1: Qt.vector4d(book.spinePos, book.side, index, book.half)
        }
    }
}
