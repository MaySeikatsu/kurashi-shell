import QtQuick
import "../../../core"

// Switch (session 28): the plain switch, refined. A knob in a track; the knob widens toward the side it will go to
// while it is held, lands with the look's overshoot and carries a small mark of its state (a bar for on, a ring for
// off), so the state is never colour alone. Static at rest.
ToggleBase {
    id: tg
    property bool hovered: false
    readonly property real corner: height / 2
    implicitWidth: 42
    implicitHeight: 24
    opacity: enabled ? 1 : 0.5
    Rectangle {
        anchors.fill: parent
        radius: Math.min(height / 2, Theme.rFull)
        color: tg.checked ? Theme.colorOr("toggle.track.on", Theme.accent) : Theme.selected
        border.width: tg.checked ? 0 : 1
        border.color: Theme.outline
        Behavior on color { enabled: Theme.timed; ColorAnimation { duration: Theme.fastMs } }
    }
    Rectangle {
        id: knob
        readonly property real d: tg.checked || tg.hovered ? 18 : 14
        width: tg.pressed ? d + 6 : d
        height: d
        radius: Math.min(height / 2, Theme.rFull)
        y: (tg.height - height) / 2
        x: tg.checked ? tg.width - width - 3 : 3 + (18 - d) / 2
        color: tg.checked ? Theme.fgOnAccent : Theme.dim
        Behavior on x { enabled: Theme.springOn; NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot } }
        Behavior on width { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.centerIn: parent
            visible: tg.checked
            width: 2; height: 8; radius: 1
            color: Theme.colorOr("toggle.track.on", Theme.accent)
        }
        Rectangle {
            anchors.centerIn: parent
            visible: !tg.checked
            width: 6; height: 6; radius: 3
            color: "transparent"
            border.width: 1.5
            border.color: Theme.selected
        }
    }
}
