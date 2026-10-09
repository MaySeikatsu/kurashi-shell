import QtQuick
import "../core"

// On/off switch (Bluetooth power). The state is the knob's side and the accent fill, not colour
// alone. Reachable by Tab; Space, Return and Enter, or a click, flip it. Emits `toggled(on)`.
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
        width: 40
        height: 22
        radius: height / 2
        color: sw.checked ? Theme.accent : Theme.containerHigh
        border.width: 1
        border.color: sw.checked ? Theme.accent : Theme.outline
        opacity: sw.enabled ? 1 : 0.5

        Rectangle {
            id: knob
            width: 16
            height: 16
            radius: 8
            y: 3
            x: sw.checked ? track.width - width - 3 : 3
            color: sw.checked ? Theme.fgOnAccent : Theme.dim
            Behavior on x {
                enabled: knob.visible
                NumberAnimation { duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
            }
        }
    }

    FocusRing {
        anchors.fill: track
        shown: sw.activeFocus
        corner: track.radius
    }
    TapHandler {
        enabled: sw.enabled
        onTapped: sw.flip()
    }
}
