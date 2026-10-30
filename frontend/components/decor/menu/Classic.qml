import QtQuick
import "../../../core"

// Classic (W53.1): a bevel-era menu row's background — the highlighted row a full-width band in `[decor] menu.fill`
// (9x's navy Hilight; the caller's selection colour when unset), a separator etched (a shadow line over a highlight line,
// 1 px in from the menu's edges). A disabled row draws nothing here: the caller embosses its text. Static.
MenuRowBase {
    id: row
    readonly property string band: Theme.decor("menu.fill", "")
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    Rectangle {
        anchors.fill: parent
        visible: row.highlighted && row.enabled && !row.separator
        color: row.band !== "" ? row.band : Theme.selected
    }
    Item {
        visible: row.separator
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 1; rightMargin: 1 }
        height: 2 * row.hair
        Rectangle { width: parent.width; height: row.hair; color: Theme.bevelDark2 }
        Rectangle { y: row.hair; width: parent.width; height: row.hair; color: Theme.bevelLight }
    }
}
