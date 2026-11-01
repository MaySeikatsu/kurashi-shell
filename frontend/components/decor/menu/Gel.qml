import QtQuick
import "../../../core"

// Gel (W53.4): a gel menu row — Mac OS X 10.2–10.4's menus (docs/ux/styles.md §5): the highlighted row a full-width band
// in `[decor] menu.fill` (the caller's selection when unset) lit like Aqua's gel — a lighter upper half, the colour below,
// a brighter foot — as strong as `menu.gloss` (0 = flat), corners `menu.radius`; a separator one hairline in the outline
// variant, inset from the menu's edges. Static.
MenuRowBase {
    id: row
    readonly property string band: Theme.decor("menu.fill", "")
    readonly property color c: band !== "" ? band : Theme.selected
    readonly property real g: Theme.decor("menu.gloss", 0.6)
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    Rectangle {
        anchors.fill: parent
        visible: row.highlighted && row.enabled && !row.separator
        radius: Math.max(0, Theme.decor("menu.radius", -1))
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(row.c, Qt.rgba(1, 1, 1, 0.38 * row.g)) }
            GradientStop { position: 0.5; color: Qt.tint(row.c, Qt.rgba(1, 1, 1, 0.12 * row.g)) }
            GradientStop { position: 0.51; color: row.c }
            GradientStop { position: 1; color: Qt.tint(row.c, Qt.rgba(1, 1, 1, 0.2 * row.g)) }
        }
    }
    Rectangle {
        visible: row.separator && Theme.decor("menu.separator", "line") === "line"
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 1; rightMargin: 1 }
        height: row.hair
        color: Theme.color("color.outline_variant", "#c4c4c4")
    }
}
