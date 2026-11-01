import QtQuick
import "../../../core"

// Flat (W53.2): a flat menu row — Windows XP's menus (docs/ux/styles.md §2, guidebookgallery.org's
// pics/gui/desktop/firstrun/winxppro-2-1.png): the highlighted row a full-width band in `[decor] menu.fill` (the caller's
// selection colour when unset), corners `menu.radius`; a separator as `menu.separator` says — one hairline in the
// outline variant (`line`, XP's #aca899 rule), etched (shadow over highlight) or `space` (nothing). Static.
MenuRowBase {
    id: row
    readonly property string band: Theme.decor("menu.fill", "")
    readonly property string sep: Theme.decor("menu.separator", "line")
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    Rectangle {
        anchors.fill: parent
        visible: row.highlighted && row.enabled && !row.separator
        radius: Math.max(0, Theme.decor("menu.radius", -1))
        color: row.band !== "" ? row.band : Theme.selected
    }
    Rectangle {
        visible: row.separator && row.sep === "line"
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 2; rightMargin: 2 }
        height: row.hair
        color: Theme.color("color.outline_variant", "#aca899")
    }
    Item {
        visible: row.separator && row.sep === "etched"
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 1; rightMargin: 1 }
        height: 2 * row.hair
        Rectangle { width: parent.width; height: row.hair; color: Theme.bevelDark2 }
        Rectangle { y: row.hair; width: parent.width; height: row.hair; color: Theme.bevelLight }
    }
}
