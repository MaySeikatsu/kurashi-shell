import QtQuick
import "../core"

// Text button. `label` is already translated by the caller. Emits `clicked` only. Reachable by Tab;
// Return, Enter and Space press it. A click does not take focus, so the ring shows for keyboard users only.
Rectangle {
    id: b
    property string label: ""
    property bool primary: false
    property bool enabled: true
    signal clicked()

    function press() { if (b.enabled) b.clicked() }

    implicitWidth: txt.implicitWidth + 2 * Theme.pad
    implicitHeight: Theme.controlH
    radius: Theme.rSm
    color: primary ? Theme.accent : Theme.containerHigh
    opacity: enabled ? 1 : 0.5
    border.width: hover.hovered && enabled ? 1 : 0
    border.color: Theme.fg

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: event => { b.press(); event.accepted = true }
    Keys.onEnterPressed: event => { b.press(); event.accepted = true }
    Keys.onSpacePressed: event => { b.press(); event.accepted = true }
    Accessible.role: Accessible.Button
    Accessible.name: b.label

    Text {
        id: txt
        anchors.centerIn: parent
        // On the accent fill the text takes on_accent (4.5:1); on the container, the normal foreground.
        color: b.primary ? Theme.fgOnAccent : Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: b.label
    }
    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        enabled: b.enabled
        onClicked: b.clicked()
    }
    FocusRing {
        anchors.fill: parent
        shown: b.activeFocus
        corner: b.radius
        stroke: b.primary ? Theme.fgOnAccent : Theme.focusRing
    }
}
