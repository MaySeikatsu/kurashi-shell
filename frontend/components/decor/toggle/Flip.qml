import QtQuick
import "../../../core"

// Flip (session 28): a rocker. Two halves, a ring on the off side and a bar on the on side; the half in effect is
// pressed down — filled, its mark lit — and the other stands up. A lip of light sits on the standing half's edge.
ToggleBase {
    id: tg
    property bool hovered: false
    readonly property real corner: Math.min(6, Theme.rFull)
    implicitWidth: 46
    implicitHeight: 24
    opacity: enabled ? 1 : 0.5
    Rectangle {
        anchors.fill: parent
        radius: tg.corner
        color: Theme.selected
        border.width: 1
        border.color: tg.hovered ? Theme.dim : Theme.outline
    }
    // The pressed half.
    Rectangle {
        x: tg.checked ? tg.width / 2 : 2
        y: 2
        width: tg.width / 2 - 2
        height: tg.height - 4
        radius: Math.max(0, tg.corner - 2)
        color: tg.checked ? Theme.colorOr("toggle.track.on", Theme.accent) : Qt.alpha(Theme.fg, 0.16)
        Behavior on x { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
        Behavior on color { enabled: Theme.timed; ColorAnimation { duration: Theme.fastMs } }
    }
    Rectangle {
        x: tg.width / 4 - 4 + 1; anchors.verticalCenter: parent.verticalCenter
        width: 8; height: 8; radius: 4
        color: "transparent"; border.width: 1.5
        border.color: tg.checked ? Theme.dim : Theme.fg
    }
    Rectangle {
        x: tg.width * 3 / 4 - 2; anchors.verticalCenter: parent.verticalCenter
        width: 2; height: 10; radius: 1
        color: tg.checked ? Theme.fgOnAccent : Theme.dim
    }
}
