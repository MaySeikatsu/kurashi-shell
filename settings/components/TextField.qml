import QtQuick
import "../core"

// Single-line editor; commits on Enter or focus loss. Shows the daemon's value while not editing.
Rectangle {
    id: f
    property string value: ""
    property string placeholder: ""
    property bool enabled: true
    property bool mono: false
    property color swatch: "transparent"
    property bool showSwatch: false
    signal accepted(string text)
    signal typing(string text)

    implicitWidth: 220
    implicitHeight: 28
    radius: Theme.rSm
    color: Theme.containerHigh
    border.width: input.activeFocus ? 1 : 0
    border.color: Theme.fg
    opacity: enabled ? 1 : 0.5

    Rectangle {
        visible: f.showSwatch
        width: 14
        height: 14
        radius: 3
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Theme.gap
        color: f.swatch
        border.width: 1
        border.color: Theme.outline
    }
    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: f.showSwatch ? Theme.gap * 2 + 14 : Theme.gap
        anchors.rightMargin: Theme.gap
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        enabled: f.enabled
        color: Theme.fg
        selectionColor: Theme.accent
        font.pixelSize: Theme.fs
        font.family: f.mono ? "monospace" : Theme.fam(text, Theme.families)
        // Re-bind to the daemon value whenever editing ends (accepted or not): what is shown is
        // what is in effect (rule 2).
        text: f.value
        onTextEdited: f.typing(text)
        onEditingFinished: {
            if (text !== f.value) f.accepted(text)
            text = Qt.binding(function () { return f.value })
        }
        Text {
            visible: input.text === "" && !input.activeFocus
            color: Theme.dim
            font: input.font
            anchors.verticalCenter: parent.verticalCenter
            text: f.placeholder
        }
    }
}
