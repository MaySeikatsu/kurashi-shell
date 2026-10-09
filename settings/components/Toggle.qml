import QtQuick
import "../core"

// Switch. `checked` is the daemon's effective value; a click, Space or Return only emits the wished value. The focus ring
// sits 3 px outside the track: an inner ring would sit on the accent fill of an ON switch (as the shell's ToggleSwitch).
Item {
    id: t
    property bool checked: false
    property bool enabled: true
    property string label: ""
    signal toggled(bool value)

    function flip() { if (t.enabled) t.toggled(!t.checked) }

    implicitWidth: track.width
    implicitHeight: Theme.controlH
    opacity: t.enabled ? 1 : 0.5
    activeFocusOnTab: t.enabled
    Keys.onSpacePressed: event => { t.flip(); event.accepted = true }
    Keys.onReturnPressed: event => { t.flip(); event.accepted = true }
    Keys.onEnterPressed: event => { t.flip(); event.accepted = true }
    Accessible.role: Accessible.CheckBox
    Accessible.name: t.label
    Accessible.checkable: true
    Accessible.checked: t.checked

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: 40
        height: 22
        radius: height / 2
        color: t.checked ? Theme.accent : Theme.containerHigh
        border.width: 1
        border.color: t.checked ? Theme.accent : Theme.outline

        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 3
            x: t.checked ? track.width - width - 3 : 3
            color: t.checked ? Theme.fgOnAccent : Theme.fg
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: t.enabled
        onClicked: t.flip()
    }
    FocusRing {
        anchors.fill: track
        anchors.margins: -3
        shown: t.activeFocus
        corner: track.radius + 3
    }
}
