import QtQuick
import "../../../core"

// State (W53.8, docs/ux/styles.md "material"): a Material 3 menu row (material-web tokens md.comp.menu, read 2026-11-01:
// list items 48 px tall on the surface-container, no band — the row under the keyboard or the pointer gets the state
// layer, on-surface at 10 % (focus) as md.sys.state's focus opacity; a selected row the secondary-container (the tonal
// `selected`, `menu.fill`). The divider: 1 px of outline-variant across the menu's width, 8 px of air round it (M3
// divider). Square: the menu's corners are the container's (4 px), not the row's. Static.
MenuRowBase {
    id: row
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    Rectangle {
        anchors.fill: parent
        visible: !row.separator && row.enabled && (row.highlighted || row.checked)
        color: row.checked ? Theme.selected : Qt.alpha(Theme.fg, 0.10)
    }
    Rectangle {
        visible: row.separator
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: row.hair
        color: Theme.color("color.outline_variant", "#49454f")
    }
}
