import QtQuick

// An item's peek (K35, I55, I67). It asks Peeks for `source` while the pointer rests on the item (after `intentMs`) or
// while the item has keyboard focus (at once), and gives the request up when neither holds. `target` is the item whose
// place the peek hangs under. Row 514: the request carries where the item's host stands — its edge and its window's place
// on the output — asked from the nearest module host round the item (an ancestor with `peekPlace()`: ModuleBase, a bar's
// zone or an edge module group, K72), so the tray icons and the island inside their modules need nothing of their own; an
// item outside any host falls back to the output's primary bar (Peeks.edgeOf). The box is the item's on its window; a
// turned item (the island in a side bar) is boxed by its corners, so the box is the one it looks like. Declared inside the
// item it describes; the item decides `hovered`, `focused` and whether a peek is offered at all.
QtObject {
    id: ps
    required property var target
    // "mod:<id>:<name>", "tray:<item>" or "island:<instance>"; "" offers no peek.
    property string source: ""
    property string output: ""
    property bool hovered: false
    property bool focused: false
    property bool enabled: true
    readonly property int intentMs: 300
    readonly property bool wanted: enabled && source !== "" && (hovered || focused)

    onWantedChanged: {
        intent.stop()
        if (!wanted) Peeks.hide(source)
        else if (focused) ask()
        else intent.restart()
    }
    // Focus taken while the pointer already asks: the peek comes at once. (Focus that starts the request is asked above.)
    onFocusedChanged: if (wanted && focused) { intent.stop(); ask() }
    property Timer intent: Timer { interval: ps.intentMs; onTriggered: ps.ask() }

    // The host's place, read when the peek is asked for (never per frame): { edge, ox, oy } or null.
    function place() {
        for (var p = ps.target; p; p = p.parent)
            if (typeof p.peekPlace === "function") return p.peekPlace()
        return null
    }
    function ask() {
        if (!wanted) return
        var b = box(), pl = place()
        Peeks.show(ps.source, ps.output, b.x, b.w, pl ? pl.edge : Peeks.edgeOf(ps.output), b.y, b.h,
                   pl ? pl.ox : 0, pl ? pl.oy : 0)
    }
    // The item's box in its window's coordinates: the bounding box of its four corners.
    function box() {
        var t = ps.target
        var p = [t.mapToItem(null, 0, 0), t.mapToItem(null, t.width, 0),
                 t.mapToItem(null, 0, t.height), t.mapToItem(null, t.width, t.height)]
        var x0 = p[0].x, x1 = p[0].x, y0 = p[0].y, y1 = p[0].y
        for (var i = 1; i < p.length; i++) {
            x0 = Math.min(x0, p[i].x); x1 = Math.max(x1, p[i].x)
            y0 = Math.min(y0, p[i].y); y1 = Math.max(y1, p[i].y)
        }
        return {x: x0, y: y0, w: x1 - x0, h: y1 - y0}
    }
}
