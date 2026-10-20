import QtQuick
import "../core"

// On/off switch (Wi-Fi and Bluetooth in quick settings). The state is the knob's side and the accent fill,
// not colour alone. Reachable by Tab; Space, Return and Enter, or a click, flip it. Emits `toggled(on)`.
// The focus ring sits 3 px outside the track: an inner ring would be the accent fill of an ON switch.
Item {
    id: sw
    property bool checked: false
    property bool enabled: true
    property string label: ""         // accessible name, already translated
    signal toggled(bool on)

    function flip() { if (sw.enabled) sw.toggled(!sw.checked) }

    implicitWidth: track.width
    implicitHeight: Theme.controlH
    activeFocusOnTab: sw.enabled
    Keys.onSpacePressed: sw.flip()
    Keys.onReturnPressed: sw.flip()
    Keys.onEnterPressed: sw.flip()
    Accessible.role: Accessible.CheckBox
    Accessible.name: sw.label
    Accessible.checked: sw.checked

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: Theme.keycap ? 46 : 40
        height: Theme.keycap ? 26 : 22
        radius: height / 2
        color: sw.checked ? Theme.accent : Theme.containerHigh
        // Keycap chrome (K42): the track keeps its ink outline in both states.
        border.width: Theme.keycap ? Theme.outlineW : 1
        border.color: Theme.keycap ? Theme.line : (sw.checked ? Theme.accent : Theme.outline)
        opacity: sw.enabled ? 1 : 0.5

        Rectangle {
            id: knob
            width: Theme.keycap ? 18 : 16
            height: width
            radius: width / 2
            y: (track.height - height) / 2
            x: sw.checked ? track.width - width - y : y
            color: Theme.keycap ? Theme.ring : (sw.checked ? Theme.fgOnAccent : Theme.dim)
            border.width: Theme.keycap ? Theme.outlineW : 0
            border.color: Theme.line
            Behavior on x {
                enabled: knob.visible && Theme.springOn
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
        }
    }

    FocusRing {
        anchors.fill: track
        anchors.margins: -3
        shown: sw.activeFocus
        corner: track.radius + 3
    }
    TapHandler {
        enabled: sw.enabled
        onTapped: sw.flip()
    }
}
