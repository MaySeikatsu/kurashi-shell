pragma Singleton
import QtQuick
import Quickshell
import "../../core"
import "../island"

// Where the last right click that opens a menu at the pointer (W82, docs/ux/context-menus.md: `desktop:<output>`,
// `bar:<output>/<edge>`) was pressed: `{output, x, y, t}` in the output's logical px. The surface that took the click
// calls `open`, which notes it and asks the daemon for the menu (`tray.menu.open`, the Stage's `tray` panel); the Stage
// stands its card there. A menu opened by key finds no fresh note and stands centred. Plain state, no timers (Ma).
Singleton {
    property var last: ({ output: "", x: 0, y: 0, t: 0 })
    function open(target, output, x, y) {
        last = { output: output, x: Math.round(x), y: Math.round(y), t: Date.now() }
        // (the pressed output, so shell.qml hands the Stage that screen: a press on a bar or the desktop does not move the
        // compositor's focus there)
        IslandGeom.notePress(output, "")
        Store.act("tray.menu.open", { id: target })
    }
}
