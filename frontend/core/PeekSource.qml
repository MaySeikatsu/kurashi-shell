import QtQuick

// A bar item's peek (K35, I55, I67). It asks Peeks for `source` while the pointer rests on the item (after `intentMs`) or
// while the item has keyboard focus (at once), and gives the request up when neither holds. `target` is the item whose
// place the peek hangs under. The request carries the bar's edge (Peeks keeps it per output: `output` names the bar) and
// the item's box on its window: a top or bottom bar spans its output, so the window's x is the output's x; a side bar
// spans the height, so the item's y and height go too (I67). A turned item (the island in a side bar) is boxed by its
// corners, so the box is the one it looks like. Declared inside the item it describes; the item decides `hovered`,
// `focused` and whether a peek is offered at all.
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

    function ask() {
        if (!wanted) return
        var b = box()
        Peeks.show(ps.source, ps.output, b.x, b.w, Peeks.edgeOf(ps.output), b.y, b.h)
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
