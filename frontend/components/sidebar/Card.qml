import QtQuick
import Quickshell
import "../../core"
import ".."

// A section's plate in a sidebar (docs/ux/sidebar.md): the container role, concentric with the column (I269), the chrome's outline (a hairline
// under flat chrome); tokens only (rule 4). Its children stack in a column inside its padding; `shown` false takes the
// section out of the column (RightColumn).
Rectangle {
    id: card
    property bool shown: true
    default property alias content: col.data
    implicitHeight: col.implicitHeight + 2 * Theme.pad
    // Concentric with the column it lies in (I269: the window's `sectionR`), else the look's radius.
    radius: QsWindow.window && QsWindow.window.sectionR !== undefined ? QsWindow.window.sectionR : Theme.rLg
    color: Theme.container
    // K62: with a pen in effect the pen draws the outline instead of the straight border.
    border.width: pen.active ? 0 : (Theme.outlineW > 0 ? Theme.outlineW : 1)
    border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
    Loader {
        id: pen
        z: 1
        anchors.fill: parent
        active: Theme.penOutline && card.visible
        sourceComponent: PenOutline {
            radius: card.radius
            color: card.border.color
            lineWidth: Theme.outlineW > 0 ? Theme.outlineW : 1
            anchor: card
        }
    }
    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: card.width - 2 * Theme.pad
        spacing: Theme.gap
    }
}
