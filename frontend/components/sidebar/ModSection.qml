import QtQuick
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
}
