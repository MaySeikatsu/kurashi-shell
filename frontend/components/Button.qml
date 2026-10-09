import QtQuick
import "../core"

// Text button. `label` is already translated by the caller (I18n.tr). Emits `clicked`; the caller
// decides which action/intent that means.
Rectangle {
    id: b
    property string label: ""
    property bool primary: false
    property bool enabled: true
    signal clicked()

    implicitWidth: txt.implicitWidth + 2 * Theme.pad
    implicitHeight: 28
    radius: Theme.rSm
    color: primary ? Theme.accent : Theme.containerHigh
    opacity: enabled ? 1 : 0.5
    border.width: hover.hovered && enabled ? 1 : 0
    border.color: Theme.fg

    Text {
        id: txt
        anchors.centerIn: parent
        color: Theme.fg
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
}
