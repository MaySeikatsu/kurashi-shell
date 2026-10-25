pragma Singleton
import QtQuick
import Quickshell

// Where an open sidebar joins its bar (W34): per output, the span of the bar's edge the column covers at rest, so a bar
// that rules its edge (line chrome) can leave its rule out there and bar and column read as one sheet — the column's
// outline runs round its fillet into the rule's end (ColumnShape, `ruled`). Published by Sidebar.qml only while the
// column stands at rest under (or beside) a ruled bar; withdrawn the moment it starts to fold. Plain state (Ma).
Singleton {
    // { "<output>": { edge, from, to } }: the bar's edge ("top", "bottom", "left", "right") and the span along it, in px
    // from the bar's start (its left end, or its top end for a side bar).
    property var openings: ({})
    function set(output, edge, from, to) {
        if (output === "") return
        var o = openings[output]
        if (o && o.edge === edge && o.from === from && o.to === to) return
        var n = Object.assign({}, openings)
        n[output] = { edge: edge, from: from, to: to }
        openings = n
    }
    function clear(output) {
        if (!openings[output]) return
        var n = Object.assign({}, openings)
        delete n[output]
        openings = n
    }
    function openingOf(output) { return openings[output] || null }
}
