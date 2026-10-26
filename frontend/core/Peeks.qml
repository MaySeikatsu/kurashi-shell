pragma Singleton
import QtQuick
import Quickshell

// The peek requests of the shell (K35, I67). The daemon holds the one peek (`runtime.ui.peek`); this decides what is asked,
// and the latest request wins. A bar item asks with `show` (on hover after its intent delay, on keyboard focus at once)
// and gives up with `hide`. The give-up waits a grace, so the pointer can reach the peek: the peek keeps itself with
// `hold` while the pointer is on it and gives up with `leave`. Nothing is asked while a card is open: the daemon refuses
// that (ui.error.peek_under_card), and the card is the bigger view.
QtObject {
    id: peeks
    readonly property int graceMs: 250
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    // The source last asked for ("" when none). A hide from any other source leaves the peek alone.
    property string owner: ""
    // The edge of each output's bar (I67), by output name: a bar reports it when it is made or its edge changes, and a
    // peek asks for the edge of the output it is on. A bar's items cannot read it from their window.
    property var edges: ({})

    function setEdge(output, edge) { edges[output] = edge }
    function edgeOf(output) { return edges[output] || "top" }
    // K71: an output may have a bar on each edge. A source whose item stands on a bar of its own says so (`place`: that
    // bar's edge and its window's place on the output, logical px), so its peek hangs beside that bar, at the item's
    // place on the output (a floating bar's window does not start at the output's corner).
    property var places: ({})
    function place(source, output, edge, ox, oy) {
        if (!source || !output) return
        places[source] = { output: output, edge: edge, ox: ox || 0, oy: oy || 0 }
    }
    function unplace(source, output) {
        var p = places[source]
        if (p && p.output === output) delete places[source]
    }

    // Asks for the peek of `source` (`mod:<id>:<name>`, `tray:<item>` or `island:<instance>`) on `output`, under the item
    // that starts at `x` and is `w` wide (output-local logical px). `edge` is the bar's edge (top when absent). A side bar's
    // peek also needs the item's `y` and `h` on it (I67).
    function show(source, output, x, w, edge, y, h) {
        if (ui.panel) return
        owner = source
        grace.stop()
        var pl = places[source]
        if (pl && pl.output !== output) pl = null
        var e = pl ? pl.edge : (edge || "top")
        var ox = pl ? pl.ox : 0, oy = pl ? pl.oy : 0
        var req = {source: source, output: output, x: Math.round(x + ox), w: Math.round(w), edge: e}
        if (e === "left" || e === "right") { req.y = Math.round(y + oy); req.h = Math.round(h) }
        Store.act("ui.peek", req)
    }
    // The pointer or the focus left `source`: its peek goes after the grace, if it is still the one asked for.
    function hide(source) {
        if (owner === source) grace.restart()
    }
    // The pointer is on the peek: it stays. The pointer left it: it goes after the grace.
    function hold() { grace.stop() }
    function leave() { if (owner !== "") grace.restart() }
    // A click answered it: it goes now.
    function dismiss() { grace.stop(); drop() }
    function drop() {
        if (owner === "") return
        owner = ""
        Store.act("ui.peek", {})
    }
    property Timer grace: Timer { interval: peeks.graceMs; onTriggered: peeks.drop() }
}
