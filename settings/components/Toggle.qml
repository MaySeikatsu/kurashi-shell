import QtQuick
import "../core"
import "decor"

// Switch. `checked` is the daemon's effective value; a click, Space or Return only emits the wished value. The focus ring
// sits 3 px outside the track: an inner ring would sit on the accent fill of an ON switch (as the shell's ToggleSwitch).
Item {
    id: t
    property bool checked: false
    property bool enabled: true
    property string label: ""
    signal toggled(bool value)

    function flip() { if (t.enabled) t.toggled(!t.checked) }

    // Session 28: the one switch of the shell (the look's `[slots] toggle`, or `theme.toggle`), as ToggleSwitch hosts it.
    DecorHost {
        id: part
        slot: "toggle"
        anchors.centerIn: parent
        width: item ? item.implicitWidth : 0
        height: item ? item.implicitHeight : 0
        onLoaded: {
            item.checked = Qt.binding(function () { return t.checked })
            item.pressed = Qt.binding(function () { return area.pressed })
            if (item.hasOwnProperty("hovered")) item.hovered = Qt.binding(function () { return area.containsMouse })
            if (item.hasOwnProperty("focused")) item.focused = Qt.binding(function () { return t.activeFocus })
        }
    }
    implicitWidth: part.ready ? part.width : track.width
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
        visible: !part.has
        anchors.centerIn: parent
        width: Theme.keycap ? 46 : 40
        height: Theme.keycap ? 26 : 22
        radius: height / 2
        color: t.checked ? Theme.accent : Theme.containerHigh
        border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
        border.color: Theme.outlineW > 0 ? Theme.outlineColor : (t.checked ? Theme.accent : Theme.outline)

        Rectangle {
            width: Theme.keycap ? 18 : 16
            height: width
            radius: width / 2
            y: (track.height - height) / 2
            x: t.checked ? track.width - width - y : y
            color: Theme.keycap ? Theme.ring : (t.checked ? Theme.fgOnAccent : Theme.fg)
            border.width: Theme.outlineW > 0 ? Theme.outlineW : 0
            border.color: Theme.line
            Behavior on x {
                enabled: Theme.springOn
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: t.enabled
        hoverEnabled: true
        onClicked: t.flip()
    }
    FocusRing {
        anchors.fill: part.ready ? part : track
        anchors.margins: -3
        shown: t.activeFocus
        corner: part.ready ? (part.item.corner !== undefined ? part.item.corner + 3 : 0) : track.radius + 3
    }
}
