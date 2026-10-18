import QtQuick

// A bar item's peek (K35, I55). It asks Peeks for `source` while the pointer rests on the item (after `intentMs`) or
// while the item has keyboard focus (at once), and gives the request up when neither holds. `target` is the item whose
// place the peek hangs under: the window of a top or bottom bar spans its output, so its mapped x is the output's x.
// Declared inside the item it describes; the item decides `hovered`, `focused` and whether a peek is offered at all.
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
        var p = ps.target.mapToItem(null, 0, 0)
        Peeks.show(ps.source, ps.output, p.x, ps.target.width)
    }
}
