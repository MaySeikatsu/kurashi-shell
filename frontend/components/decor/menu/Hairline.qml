import QtQuick
import "../../../core"
import ".."

// Hairline (W53.6): a dark-fantasy menu's selected row — Dark Souls' (docs/ux/styles.md §9.3): no band at rest; the
// highlighted row a soft band of `[decor] menu.fill` that fades out toward both ends, held between two device-pixel
// hairlines in `menu.line` (the gold) that fade the same way, with `menu.mark` (a small diamond) at its start. A separator
// is a hairline in `menu.line` faded at its ends. Colours from roles (rule 4); static.
MenuRowBase {
    id: row
    readonly property string fillRole: Theme.decor("menu.fill", "")
    readonly property color fill: fillRole !== "" ? fillRole : Theme.selected
    readonly property string lineRole: Theme.decor("menu.line", "")
    readonly property color line: lineRole !== "" ? lineRole : Theme.accent
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool lit: highlighted && enabled && !separator

    component Fade: Rectangle {
        property color c
        property real peak: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(c, 0) }
            GradientStop { position: 0.12; color: Qt.alpha(c, peak) }
            GradientStop { position: 0.7; color: Qt.alpha(c, peak * 0.85) }
            GradientStop { position: 1; color: Qt.alpha(c, 0) }
        }
    }
    Fade { visible: row.lit; anchors.fill: parent; c: row.fill; peak: 0.9 }
    Fade { visible: row.lit; width: parent.width; height: row.hair; c: row.line }
    Fade { visible: row.lit; width: parent.width; y: parent.height - row.hair; height: row.hair; c: row.line }
    Bullet {
        visible: row.lit && kind !== "none"
        x: 3
        anchors.verticalCenter: parent.verticalCenter
        kind: Theme.decor("menu.mark", "none")
        size: 6
        ink: row.line
    }
    Fade { visible: row.separator; width: parent.width; y: Math.round(parent.height / 2); height: row.hair; c: row.line; peak: 0.6 }
}
