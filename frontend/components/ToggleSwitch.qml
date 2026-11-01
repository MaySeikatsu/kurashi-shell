import QtQuick
import Quickshell
import "../core"
import "decor"

// On/off switch (Wi-Fi and Bluetooth in quick settings). The state is the knob's side and the accent fill,
// not colour alone. Reachable by Tab; Space, Return and Enter, or a click, flip it. Emits `toggled(on)`.
// The focus ring sits 3 px outside the track: an inner ring would be the accent fill of an ON switch.
Item {
    id: sw
    property bool checked: false
    property bool enabled: true
    property string label: ""         // accessible name, already translated
    signal toggled(bool on)
    // K61 (docs/ux/texture.md "Controls"): the track and the knob are opaque, so both carry the relief, in a window that
    // shares its sheet (Relief makes its own otherwise).
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool ownRelief: Theme.texControls && !!(qsw && qsw.tileSheet)

    function flip() { if (sw.enabled) sw.toggled(!sw.checked) }

    // W53.7/8 (K80): the look's toggle part (`[slots] toggle`, contract decor/toggle/ToggleBase.qml) draws the switch
    // instead of the track and knob — a check box (9x), M3's switch with its thumb icon; nothing is made without one.
    DecorHost {
        id: part
        slot: "toggle"
        anchors.centerIn: parent
        width: item ? item.implicitWidth : 0
        height: item ? item.implicitHeight : 0
        onLoaded: {
            item.checked = Qt.binding(function () { return sw.checked })
            item.pressed = Qt.binding(function () { return tap.pressed })
            if (item.hasOwnProperty("enabled")) item.enabled = Qt.binding(function () { return sw.enabled })
            if (item.hasOwnProperty("hovered")) item.hovered = Qt.binding(function () { return hover.hovered })
            if (item.hasOwnProperty("focused")) item.focused = Qt.binding(function () { return sw.activeFocus })
        }
    }
    HoverHandler { id: hover; enabled: part.has }

    implicitWidth: part.ready ? part.width : track.width
    implicitHeight: part.ready ? Math.max(Theme.controlH, part.height) : Theme.controlH
    activeFocusOnTab: sw.enabled
    Keys.onSpacePressed: sw.flip()
    Keys.onReturnPressed: sw.flip()
    Keys.onEnterPressed: sw.flip()
    Accessible.role: Accessible.CheckBox
    Accessible.name: sw.label
    Accessible.checked: sw.checked

    Rectangle {
        id: track
        visible: !part.has
        anchors.centerIn: parent
        width: Theme.ringW > 0 ? 46 : 40
        height: Theme.ringW > 0 ? 26 : 22
        radius: Math.min(height / 2, Theme.rFull)
        color: sw.checked ? Theme.accent : Theme.containerHigh
        // Keycap chrome (K42): the track keeps its ink outline in both states.
        border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
        border.color: Theme.outlineW > 0 ? Theme.outlineColor : (sw.checked ? Theme.accent : Theme.outline)
        opacity: sw.enabled ? 1 : 0.5

        // The relief over the track, under the knob (the outline stays flat).
        Loader {
            active: sw.ownRelief
            anchors.fill: parent
            anchors.margins: track.border.width
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, track.radius - track.border.width) }
        }
        Rectangle {
            id: knob
            width: Theme.ringW > 0 ? 18 : 16
            height: width
            radius: Math.min(width / 2, Theme.rFull)
            y: (track.height - height) / 2
            x: sw.checked ? track.width - width - y : y
            color: Theme.ringW > 0 ? Theme.ring : (sw.checked ? Theme.fgOnAccent : Theme.dim)
            border.width: Theme.ringW > 0 ? Theme.outlineW : 0
            border.color: Theme.outlineColor
            // The relief over the knob (its ring stays flat).
            Loader {
                active: sw.ownRelief
                anchors.fill: parent
                anchors.margins: knob.border.width
                sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, knob.radius - knob.border.width) }
            }
            Behavior on x {
                enabled: knob.visible && Theme.springOn
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
        }
    }

    FocusRing {
        anchors.fill: part.ready ? part : track
        anchors.margins: -3
        shown: sw.activeFocus
        corner: part.ready ? (part.item.corner !== undefined ? part.item.corner + 3 : 0) : (track.radius > 0 ? track.radius + 3 : 0)
    }
    TapHandler {
        id: tap
        enabled: sw.enabled
        onTapped: sw.flip()
    }
}
