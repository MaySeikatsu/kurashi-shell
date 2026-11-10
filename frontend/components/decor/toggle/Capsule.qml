import QtQuick
import "../../../core"

// Capsule (session 28): a wide track and a flat, light knob that fills its height; held, the knob stretches toward the
// other side, as if pulled. The state is the knob's side and the track's fill, with a short bar (on) or ring (off) at
// the free end of the track.
ToggleBase {
    id: tg
    property bool hovered: false
    readonly property real corner: height / 2
    implicitWidth: 48
    implicitHeight: 26
    opacity: enabled ? 1 : 0.5
    Rectangle {
        anchors.fill: parent
        radius: Math.min(height / 2, Theme.rFull)
        color: tg.checked ? Theme.colorOr("toggle.track.on", Theme.accent) : Theme.containerHigh
        Behavior on color { enabled: Theme.timed; ColorAnimation { duration: Theme.stdMs } }
        Rectangle {
            visible: tg.checked
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 2; height: 9; radius: 1
            color: Theme.fgOnAccent; opacity: 0.8
        }
        Rectangle {
            visible: !tg.checked
            x: parent.width - 17; anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4
            color: "transparent"; border.width: 1.5; border.color: Theme.dim
        }
    }
    Rectangle {
        width: tg.pressed ? 28 : 22
        height: 22
        radius: Math.min(11, Theme.rFull)
        y: 2
        x: tg.checked ? tg.width - width - 2 : 2
        color: tg.checked ? Theme.fgOnAccent : Theme.fg
        Behavior on x { enabled: Theme.springOn; NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot } }
        Behavior on width { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
    }
}
