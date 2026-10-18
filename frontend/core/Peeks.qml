pragma Singleton
import QtQuick
import Quickshell

// The peek requests of the shell (K35). The daemon holds the one peek (`runtime.ui.peek`); this decides what is asked,
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

    // Asks for the peek of `source` (`mod:<id>:<name>`, `tray:<item>` or `island:<instance>`) on `output`, under the item
    // that starts at `x` and is `w` wide (output-local logical px).
    function show(source, output, x, w) {
        if (ui.panel) return
        owner = source
        grace.stop()
        Store.act("ui.peek", {source: source, output: output, x: Math.round(x), w: Math.round(w)})
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
