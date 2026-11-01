import QtQuick
import "../../../core"
import ".."

// Block (W53.6): a game list's row — NieR:Automata's menus (docs/ux/styles.md §9.2): every row a pale band at rest
// (`[decor] menu.rest`, "" = none) with its square bullet (`menu.mark`, Bullet.qml), and the highlighted row a solid
// block in `menu.fill` with the text and the bullet inverted (`menu.on`), the block wiping in from the row's start when
// `menu.wipe` is on (a one-shot of the look's fast time; instant under reduce motion); corners `menu.radius`. Without a
// rest band the mark shows on the highlighted row only (the pastel heart). A separator is a hairline in the outline
// variant. Every colour from roles (rule 4); idle = 0 frames.
MenuRowBase {
    id: row
    readonly property string fillRole: Theme.decor("menu.fill", "")
    readonly property color fill: fillRole !== "" ? fillRole : Theme.selected
    readonly property string onRole: Theme.decor("menu.on", "")
    readonly property color on: onRole !== "" ? onRole : Theme.fgOnSelected
    readonly property string restRole: Theme.decor("menu.rest", "")
    readonly property string mark: Theme.decor("menu.mark", "none")
    readonly property real r: Math.max(0, Theme.decor("menu.radius", -1))
    readonly property bool wipes: Theme.decor("menu.wipe", false) === true && Theme.motionKind !== "none"
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool lit: highlighted && enabled && !separator
    // How far the block has wiped across (0…1).
    property real reach: lit ? 1 : 0
    Behavior on reach {
        enabled: row.wipes
        NumberAnimation { duration: Math.max(90, Theme.fastMs * 0.6); easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        visible: row.restRole !== "" && !row.separator
        radius: row.r
        color: row.restRole !== "" ? row.restRole : "transparent"
        opacity: row.enabled ? 1 : 0.5
    }
    Rectangle {
        visible: row.reach > 0 && !row.separator
        width: Math.round(parent.width * row.reach)
        height: parent.height
        radius: row.r
        color: row.fill
    }
    Bullet {
        visible: !row.separator && kind !== "none" && (row.lit || row.restRole !== "")
        x: Math.max(2, Math.round((10 - width) / 2))
        anchors.verticalCenter: parent.verticalCenter
        kind: row.mark
        size: Math.max(4, Math.min(7, Math.round(row.height * 0.16)))
        ink: row.lit ? row.on : Theme.fg
        opacity: row.enabled ? 1 : 0.45
    }
    Rectangle {
        visible: row.separator && Theme.decor("menu.separator", "line") === "line"
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 4; rightMargin: 4 }
        height: row.hair
        color: Theme.color("color.outline_variant", "#aba68d")
    }
}
