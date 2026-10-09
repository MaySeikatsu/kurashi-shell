import QtQuick
import "../core"

// Switch. `checked` is the daemon's effective value; a click, Space or Return only emits the wished value.
Rectangle {
    id: t
    property bool checked: false
    property bool enabled: true
    property string label: ""
    signal toggled(bool value)

    function flip() { if (t.enabled) t.toggled(!t.checked) }

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? Theme.accent : Theme.containerHigh
    border.width: 1
    border.color: Theme.outline
    opacity: enabled ? 1 : 0.5

    activeFocusOnTab: t.enabled
    Keys.onSpacePressed: event => { t.flip(); event.accepted = true }
    Keys.onReturnPressed: event => { t.flip(); event.accepted = true }
    Keys.onEnterPressed: event => { t.flip(); event.accepted = true }
    Accessible.role: Accessible.CheckBox
    Accessible.name: t.label
    Accessible.checkable: true
    Accessible.checked: t.checked

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
        // The switch keeps its 22 px; the hit area grows to the control height (32 px floor).
        anchors.margins: -Math.max(0, (Theme.controlH - t.height) / 2)
        enabled: t.enabled
        onClicked: t.flip()
    }
    FocusRing {
        anchors.fill: parent
        shown: t.activeFocus
        corner: t.radius
    }
}
