import QtQuick
import "../core"

// Switch. `checked` is the daemon's effective value; a click only emits the wished value.
Rectangle {
    id: t
    property bool checked: false
    property bool enabled: true
    signal toggled(bool value)

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? Theme.accent : Theme.containerHigh
    border.width: 1
    border.color: Theme.outline
    opacity: enabled ? 1 : 0.5

    Rectangle {
        width: 16
        height: 16
        radius: 8
        y: 3
        x: t.checked ? t.width - width - 3 : 3
        color: Theme.fg
    }
    MouseArea {
        anchors.fill: parent
        enabled: t.enabled
        onClicked: t.toggled(!t.checked)
    }
}
