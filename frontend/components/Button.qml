import QtQuick
import "../core"

// Text button. `label` is already translated by the caller (I18n.tr). Emits `clicked`; the caller
// decides which action/intent that means. Reachable by Tab; Return, Enter and Space press it.
Rectangle {
    id: b
    property string label: ""
    property bool primary: false
    property bool enabled: true
    signal clicked()

    function press() { if (b.enabled) b.clicked() }

    implicitWidth: txt.implicitWidth + 2 * Theme.pad
    implicitHeight: 28
    radius: Theme.rSm
    color: primary ? Theme.accent : Theme.containerHigh
    opacity: enabled ? 1 : 0.5
    border.width: hover.hovered && enabled ? 1 : 0
    border.color: Theme.fg

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: b.press()
    Keys.onEnterPressed: b.press()
    Keys.onSpacePressed: b.press()
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
        // The hit area grows to the control height (32 px floor); the drawn button keeps its size.
        anchors.margins: -Math.max(0, (Theme.controlH - b.height) / 2)
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
