import QtQuick
import "../../../core"

// Capsule (W53.2): a glass-era menu row — Windows 7's menus and lists (docs/ux/styles.md §3; 7.css `--w7-li-*`, the
// Windows 7 UX guide's jump list, learn.microsoft.com/…/uxguide/images/winenv-taskbar-image1.png): the highlighted row a
// soft capsule `menu.radius` round (3) with a 1 px rim in the accent's pale tint, filled light to a paler blue and back;
// a separator one hairline in the outline variant, inset as 7's jump-list rules are. Static.
MenuRowBase {
    id: row
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property color tint: Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.22))
    Rectangle {
        anchors { fill: parent; leftMargin: 2; rightMargin: 2; topMargin: 1; bottomMargin: 1 }
        visible: row.highlighted && row.enabled && !row.separator
        radius: Theme.decor("menu.radius", -1) >= 0 ? Theme.decor("menu.radius", -1) : 3
        border.width: row.hair
        border.color: Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.45))
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(row.tint, 1.06) }
            GradientStop { position: 0.9; color: row.tint }
            GradientStop { position: 1; color: Qt.lighter(row.tint, 1.04) }
        }
    }
    Rectangle {
        visible: row.separator
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 28; rightMargin: 4 }
        height: row.hair
        color: Theme.color("color.outline_variant", "#d5dfe5")
    }
}
