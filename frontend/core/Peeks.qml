pragma Singleton
import QtQuick
import Quickshell

// The peek requests of the shell (K35, I67). The daemon holds the one peek (`runtime.ui.peek`); this decides what is asked,
// and the latest request wins. A module asks with `show` (on hover after its intent delay, on keyboard focus at once)
// and gives up with `hide`. The give-up waits a grace, so the pointer can reach the peek: the peek keeps itself with
// `hold` while the pointer is on it and gives up with `leave`. Nothing is asked while a card is open: the daemon refuses
// that (ui.error.peek_under_card), and the card is the bigger view.
QtObject {
    id: peeks
    readonly property int graceMs: 250
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    // The source last asked for ("" when none). A hide from any other source leaves the peek alone.
    property string owner: ""
    // The edge of each output's primary bar (I67), by output name: a bar reports it when it is made or its edge changes.
    // Only a source outside any module host falls back to it (PeekSource asks with its host's own edge, row 514).
    property var edges: ({})

    function setEdge(output, edge) { edges[output] = edge }
    function edgeOf(output) { return edges[output] || "top" }

    // Asks for the peek of `source` (`mod:<id>:<name>`, `tray:<item>` or `island:<instance>`) on `output`, under the item
    // that starts at `x` and is `w` wide on its window. `edge` is its host's edge (top when absent) and `ox`, `oy` the
    // window's place on the output (row 514: a host that is not a full-width bar — a floating bar, an edge module group —
    // does not start at the output's corner), so the request is in output-local logical px. A side host's peek also needs
    // the item's `y` and `h` (I67).
    function show(source, output, x, w, edge, y, h, ox, oy) {
        if (ui.panel) return
        owner = source
        grace.stop()
        var e = edge || "top"
        var req = {source: source, output: output, x: Math.round(x + (ox || 0)), w: Math.round(w), edge: e}
        if (e === "left" || e === "right") { req.y = Math.round(y + (oy || 0)); req.h = Math.round(h) }
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
