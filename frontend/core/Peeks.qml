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
        if (ui.panel || (ui.tray || "") !== "" || hoverOwner !== "") return
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

    // ---- Open on hover (I458, K113, docs/ux/bar-hover.md): a bar module opens on hover, as Caelestia's popouts ----
    // `bar.hover`: "preview" the small peek (above), "card" the module's card where it has one (else its preview),
    // "menu" the module's own menu (its right click). A module named in `bar.hover_preview|card|menu` takes that one
    // whatever the bar does. What a hover opened closes when the pointer has left both the module and what it opened
    // for `hoverGraceMs`; what a click opened is left alone. No timer runs while nothing is hovered (Ma).
    readonly property var cfgValues: (Store.docs["config"] || ({})).values || ({})
    function cfg(key, dflt) { var e = cfgValues[key]; return e && e.value !== undefined ? e.value : dflt }
    readonly property string hoverBar: String(cfg("bar.hover", "preview"))
    readonly property var hoverLists: ({
        preview: cfg("bar.hover_preview", []) || [], card: cfg("bar.hover_card", []) || [], menu: cfg("bar.hover_menu", []) || []
    })
    // The module's own choice ("" when it follows the bar), and what holds for it.
    function hoverOwn(mid) {
        var l = hoverLists
        return l.card.indexOf(mid) >= 0 ? "card" : (l.menu.indexOf(mid) >= 0 ? "menu" : (l.preview.indexOf(mid) >= 0 ? "preview" : ""))
    }
    function hoverModeOf(mid) { return hoverOwn(mid) || hoverBar }
    readonly property int hoverIntentMs: 220
    readonly property int hoverGraceMs: 380
    // The module whose card or menu a hover opened ("" when none, or when a click opened what is open).
    property string hoverOwner: ""
    readonly property bool cardOpen: (ui.panel || "") !== "" || (ui.tray || "") !== "" || ui.launcher === true
    onCardOpenChanged: if (!cardOpen) { hoverOwner = ""; hoverGrace.stop() }
    function hoverOpened(mid) { hoverOwner = mid; hoverGrace.stop() }
    function hoverLeft(mid) { if (hoverOwner === mid) hoverGrace.restart() }
    // The pointer is on what the hover opened: it stays. It left: it goes after the grace. A press in it keeps it: the
    // user is using it, so it is theirs now, as if a click had opened it.
    function hoverHold() { hoverGrace.stop() }
    function hoverLeave() { if (hoverOwner !== "" && overlayHolds.length === 0) hoverGrace.restart() }
    function hoverKeep() { hoverOwner = ""; hoverGrace.stop() }
    // W72: a window of another process over the card (a mod's overlay: the web dock's page, which its panel reports) holds
    // it as the card does: `hoverOverlay(key, on)`. The card says when the pointer is on it (`onCard`, Stage), so the
    // pointer moving from the overlay onto the card — whose enter comes before the overlay's leave arrives — keeps it.
    property bool onCard: false
    property var overlayHolds: []
    function hoverOverlay(key, on) {
        var i = overlayHolds.indexOf(key)
        if (on && i < 0) { overlayHolds = overlayHolds.concat([key]); hoverGrace.stop() }
        else if (!on && i >= 0) {
            overlayHolds = overlayHolds.filter(function (k) { return k !== key })
            if (!onCard) hoverLeave()
        }
    }
    property Timer hoverGrace: Timer {
        interval: peeks.hoverGraceMs
        onTriggered: if (peeks.hoverOwner !== "") { peeks.hoverOwner = ""; Store.act("ui.close") }
    }
}
