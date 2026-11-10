import QtQuick
import "../../../core"

// Lamp (session 28): a housing with a lens. Off, the lens is dark glass; on, it is lit in the accent and throws a
// little light on the housing round it. Pressed, the housing sinks a pixel. The light comes on over the standard time.
ToggleBase {
    id: tg
    property bool hovered: false
    readonly property real corner: Math.min(7, Theme.rFull)
    implicitWidth: 40
    implicitHeight: 24
    opacity: enabled ? 1 : 0.5
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: tg.pressed ? 1 : 0
        radius: tg.corner
        color: Theme.containerHigh
        border.width: 1
        border.color: tg.hovered ? Theme.dim : Theme.outline
        // The light thrown on the housing: rings round the lens, fainter outward.
        Repeater {
            model: 3
            Rectangle {
                required property int index
                anchors.centerIn: lens
                width: lens.width + 6 + index * 6; height: width; radius: width / 2
                color: Qt.alpha(Theme.accent, tg.checked ? 0.22 - index * 0.07 : 0)
                Behavior on color { enabled: Theme.timed; ColorAnimation { duration: Theme.stdMs } }
            }
        }
        Rectangle {
            id: lens
            x: parent.width - width - 7
            anchors.verticalCenter: parent.verticalCenter
            width: 10; height: 10; radius: 5
            color: tg.checked ? Theme.accent : Qt.alpha(Theme.fg, 0.22)
            border.width: 1
            border.color: tg.checked ? Qt.lighter(Theme.accent, 1.35) : Theme.dim
            Behavior on color { enabled: Theme.timed; ColorAnimation { duration: Theme.stdMs } }
        }
        // The label plate: a bar for on, a ring for off (never colour alone).
        Rectangle {
            visible: tg.checked
            x: 9; anchors.verticalCenter: parent.verticalCenter
            width: 2; height: 9; radius: 1; color: Theme.fg
        }
        Rectangle {
            visible: !tg.checked
            x: 6; anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 8; radius: 4; color: "transparent"; border.width: 1.5; border.color: Theme.dim
        }
    }
}
