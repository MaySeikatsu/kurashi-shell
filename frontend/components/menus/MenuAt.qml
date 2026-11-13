pragma Singleton
import QtQuick
import Quickshell
import "../../core"
import "../island"

// Opens a menu at the pointer (W82, docs/ux/context-menus.md: `desktop:<output>`, `bar:<output>/<edge>`) and says where:
// `last` = `{target, output, x, y, t}` in the output's logical px; the Stage stands its card there.
// - The rows come with the card: the schema document is asked for at the press and the menu is opened once it is here,
//   so the card does not open short and grow (Ma: watched from the press until the menu's own watch holds it, nothing
//   while no menu is wanted).
// - A press for the menu that is open moves it there (the daemon would close it for the same id).
// A menu opened by key finds no fresh note and stands centred. No timers run while idle.
Singleton {
    id: ma
    property var last: ({ target: "", output: "", x: 0, y: 0, t: 0 })
    // The menu waiting for its rows, and whether it is still to be asked for.
    property string pending: ""
    property bool asking: false
    Watch { doc: "schema.settings"; active: ma.pending !== "" }
    readonly property bool rowsHere: Store.docs["schema.settings"] !== undefined
    // Test only (KURASHI_STAGE_DEBUG=1): when the menu was asked for, and whether its rows were here.
    readonly property bool debugLog: Quickshell.env("KURASHI_STAGE_DEBUG") === "1"

    function open(target, output, x, y) {
        last = { target: target, output: output, x: Math.round(x), y: Math.round(y), t: Date.now() }
        // (the pressed output, so shell.qml hands the Stage that screen: a press on a bar or the desktop does not move the
        // compositor's focus there)
        IslandGeom.notePress(output, "")
        var u = Store.docs["runtime.ui"] || {}
        if (u.panel === "tray" && u.tray === target) return
        pending = target
        asking = true
        if (rowsHere) send()
        else limit.restart()
    }
    function send() {
        limit.stop()
        if (!asking) return
        asking = false
        if (debugLog) console.log("menu-at open " + pending + " rows=" + rowsHere + " after " + (Date.now() - last.t) + " ms")
        Store.act("tray.menu.open", { id: pending })
        // (the menu's provider takes the watch over as the daemon names it; held a moment longer so it never drops)
        release.restart()
    }
    onRowsHereChanged: if (rowsHere && asking) send()
    // (no answer: open anyway, the rows follow as they come)
    Timer { id: limit; interval: 800; onTriggered: ma.send() }
    Timer { id: release; interval: 1500; onTriggered: if (!ma.asking) ma.pending = "" }
}
