import QtQuick
import "../core"

// A link in words: an action that reads as text ("open", "Island"). Reachable by Tab; Return and Space activate it, as
// does a click. The underline shows hover and focus, not colour alone.
Item {
    id: l
    property string text: ""
    property bool enabled: true
    signal activated()

    implicitWidth: t.implicitWidth + 4
    implicitHeight: Theme.controlH - 8
    activeFocusOnTab: l.enabled
    Keys.onReturnPressed: event => { l.activated(); event.accepted = true }
    Keys.onEnterPressed: event => { l.activated(); event.accepted = true }
    Keys.onSpacePressed: event => { l.activated(); event.accepted = true }
    Accessible.role: Accessible.Link
    Accessible.name: l.text

    Text {
        id: t
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        color: l.enabled ? Theme.fg : Theme.dim
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        font.underline: hov.hovered || l.activeFocus
        text: l.text
    }
    HoverHandler {
        id: hov
        enabled: l.enabled
    }
    MouseArea {
        anchors.fill: parent
        enabled: l.enabled
        onClicked: l.activated()
    }
    FocusRing {
        anchors.fill: parent
        shown: l.activeFocus
        corner: Theme.rSm
    }
}
