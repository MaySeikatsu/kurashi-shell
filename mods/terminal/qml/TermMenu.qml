import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components

// A menu of the terminal's own (W85; docs/ux/terminal.md "Tabs"): the shell's menu — TrayMenu in a MenuCard, the same
// rows, marks, keys and look as every right-click menu (docs/ux/context-menus.md) — hung from a key of a place (the tab
// row's "+" and its chevron). It is a layer window of its own over the output, mapped while open only (Ma), above the
// terminal's text window (which lies over the well and would cover a menu drawn in the place), and it holds the keyboard
// while open: Up/Down, Right/Left, Enter, Esc. A press outside the card closes it and goes nowhere else (the shell's
// click-away). `tree` is TrayMenu's; `chosen(id)` is sent for a row and the menu closes.
PanelWindow {
    id: tm
    // The tree while open; null while closed.
    property var tree: null
    // A heading over the rows ("" for none) and the card's accessible name.
    property string title: ""
    property string a11yName: ""
    // Where the key it hangs from stands, in logical px on its output: {x, y, width, height}.
    property var anchorRect: ({ x: 0, y: 0, width: 0, height: 0 })
    readonly property bool open: tree !== null
    // The terminal's window lets go of the keyboard while the menu is out (`terminal.hold`).
    onOpenChanged: Store.act("terminal.hold", { on: open })
    Component.onDestruction: if (open) Store.act("terminal.hold", { on: false })
    signal chosen(int id)

    function show(onScreen, rect, t, heading, name) {
        if (onScreen) screen = onScreen
        anchorRect = rect
        title = heading || ""
        a11yName = name || title
        tree = t
        Qt.callLater(function () { if (tm.open && body.item) body.item.forceActiveFocus() })
    }
    function close() {
        if (!open) return
        tree = null
    }

    visible: open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "kurashi-terminal-menu"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Loader {
        id: body
        anchors.fill: parent
        active: tm.open
        sourceComponent: Item {
            // (fades in on the look's quick step; with reduced motion that step is 0: no fade)
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: Theme.quickMs } }
            focus: true
            Keys.onPressed: event => {
                if (menu.handleKey(event.key)) { event.accepted = true; return }
                if (event.key === Qt.Key_Escape) tm.close()
                event.accepted = true
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: tm.close()
            }
            MenuCard {
                id: card
                readonly property real pad: Theme.pad
                readonly property var r: tm.anchorRect
                readonly property real roomBelow: tm.height - (r.y + r.height) - Theme.gap
                readonly property bool below: roomBelow >= height || roomBelow >= r.y
                width: Math.min(tm.width - 2 * Theme.gap, 320)
                height: Math.min((below ? roomBelow : r.y - Theme.gap) - Theme.xs, col.implicitHeight + 2 * pad)
                // Its end edge under the key's end edge (it grows toward the place's middle), kept on the output.
                x: Math.max(Theme.gap, Math.min(tm.width - width - Theme.gap, r.x + r.width - width))
                y: below ? r.y + r.height + Theme.xs : r.y - height - Theme.xs
                Accessible.role: Accessible.PopupMenu
                Accessible.name: tm.a11yName
                // (a press on the card is the card's: it never reaches the click-away under it)
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
                Column {
                    id: col
                    x: card.pad
                    y: card.pad
                    width: card.width - 2 * card.pad
                    spacing: Theme.gap
                    Text {
                        visible: tm.title !== ""
                        width: col.width
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fsTitle
                        font.family: Theme.fam(text, Theme.families)
                        text: tm.title
                    }
                    TrayMenu {
                        id: menu
                        objectName: "terminal-menu"
                        width: col.width
                        tree: tm.tree
                        onChosen: id => { tm.chosen(id); Qt.callLater(tm.close) }
                    }
                }
            }
        }
    }
}
