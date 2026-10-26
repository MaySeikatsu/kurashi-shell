import QtQuick
import Quickshell
import "../../core"

// A mod panel as a right-sidebar section (`mod:<id>:<panel>`, K26): its Panel.qml through ModLoader, on a Card, given
// the card's width. A mod that is off (or has no such panel) has no component: the section takes no space (`shown`).
Card {
    id: ms
    property string mod: ""
    property string panel: ""
    shown: loader.resolved !== ""
    ModLoader {
        id: loader
        width: ms.width - 2 * Theme.pad
        height: item ? item.implicitHeight : 0
        provide: ms.panel !== "" ? "panel:" + ms.panel : ""
        mod: ms.mod
    }
    // Where the panel rests in the right sidebar's window (optional `placement`, W30; see LeftColumn).
    Placement {
        id: placement
        target: loader.item !== null && loader.item.placement !== undefined ? loader.item : null
        win: ms.Window.window
        origin: ms.QsWindow.window && ms.QsWindow.window.placementOrigin !== undefined ? ms.QsWindow.window.placementOrigin : Qt.point(0, 0)
        output: ms.Screen.name
        side: "right"
    }
    Binding {
        target: loader.item
        property: "placement"
        value: placement.value
        when: placement.target !== null
    }
}
