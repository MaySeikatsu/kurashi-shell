import QtQuick

// The notebook's measures (W69; docs/ux/webdock.md "Page styles" › Notebook) for a card of `width` × `height` whose
// binding runs along `edge` (the dock's side). Worked out in the binding's frame — `a` along the binding, `d` across it
// from the card's edge on the dock's side — and placed per edge by `pt`/`rect`, so the cover, the sheets and the coil are
// written once for all four edges. Pure numbers: the three layers (NotebookBack, NotebookSheet, NotebookWire) read them.
QtObject {
    id: g

    property real width: 0
    property real height: 0
    property string edge: "right"

    readonly property bool sideways: edge === "left" || edge === "right"
    // The binding's length and the card's depth away from it.
    readonly property real along: sideways ? height : width
    readonly property real away: sideways ? width : height
    // Across the binding: the coil's axis, the cover's edge under it, the sheets' bound edge, the slots' middles.
    readonly property real axisD: 5
    readonly property real coverD: 8
    readonly property real sheetD: 14
    readonly property real holeD: 23
    // The cover shows this far round the sheets on their three free sides; two sheets lie under the top one.
    readonly property real lip: 6
    // The coil: a pair of loops every `pitch` px, the two loops `twin` px apart, clear of the sheet's ends.
    readonly property real pitch: 28
    readonly property real twin: 7
    readonly property real endRoom: 14
    readonly property int pairs: Math.max(0, Math.floor((along - 2 * lip - 2 * endRoom - twin) / pitch) + 1)
    readonly property real firstA: (along - (pairs - 1) * pitch - twin) / 2

    // A point (a, d) of the binding's frame in the card's px.
    function pt(a, d) {
        if (edge === "right") return Qt.point(width - d, a)
        if (edge === "left") return Qt.point(d, a)
        if (edge === "bottom") return Qt.point(a, height - d)
        return Qt.point(a, d)
    }
    // A box [a0, a1] × [d0, d1] of the binding's frame in the card's px.
    function rect(a0, a1, d0, d1) {
        var p = pt(a0, d0), q = pt(a1, d1)
        return Qt.rect(Math.min(p.x, q.x), Math.min(p.y, q.y), Math.abs(q.x - p.x), Math.abs(q.y - p.y))
    }
    readonly property rect cover: rect(0, along, coverD, away)
    readonly property rect sheet: rect(lip, along - lip, sheetD, away - lip)
    // The sheets under the top one: each a little further out on the free side, so their edges show there.
    readonly property rect under1: rect(lip + 1, along - lip + 1.5, sheetD, away - lip + 2)
    readonly property rect under2: rect(lip + 2, along - lip + 3, sheetD, away - lip + 4)
    // The loops' places along the binding: each pair's first loop, then the second `twin` px on.
    readonly property var loops: {
        var out = []
        for (var i = 0; i < pairs; i++) {
            out.push(firstA + i * pitch)
            out.push(firstA + i * pitch + twin)
        }
        return out
    }
    // Which corners of a box lie on the free side (the binding's are square: punched paper, a bound cover).
    readonly property bool bindLeft: edge === "left"
    readonly property bool bindRight: edge === "right"
    readonly property bool bindTop: edge === "top"
    readonly property bool bindBottom: edge === "bottom"
}
