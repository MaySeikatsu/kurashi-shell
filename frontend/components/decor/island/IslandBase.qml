import QtQuick

// The contract of an island part (`[slots] island`, W53.5): drawn over the island's pill, filling it. `face` is the face
// shown, `typing` true while its line types out (`[decor] island.reveal = type`), `vertical` on a side bar. A part may ask
// for the pill's corner (`radius` ≥ 0; -1 = the island's pill) and keep `lead` px at the pill's start for a mark (top and
// bottom bars only). Static: one paint per size and colour.
Item {
    property string face: ""
    property bool vertical: false
    property bool typing: false
    property real radius: -1
    property real lead: 0
}
