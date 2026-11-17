import QtQuick
import qs.core
import qs.components

// The pickers' search field (the library's and Wallhaven's): a field with its placeholder, Escape clearing it first
// (a second Escape goes on to the host: the card or the menu closes). `liveMs` > 0 sends `edited` that long after the
// last key (the library filters while typing); Return sends `submitted` (Wallhaven searches), Down `down`.
Rectangle {
    id: box
    property alias text: field.text
    property alias input: field
    property string placeholder: ""
    property int liveMs: 0
    property int maxLength: 200
    signal edited(string text)
    signal submitted(string text)
    signal down()
    signal cleared()

    implicitWidth: 240
    height: Theme.controlH
    radius: Theme.rSm
    color: Theme.containerHigh
    border.width: field.activeFocus ? 1 : 0
    border.color: Theme.focusRing

    TextInput {
        id: field
        anchors.fill: parent
        anchors.leftMargin: Theme.gap
        anchors.rightMargin: Theme.gap
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: Theme.fg
        selectionColor: Theme.accent
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        activeFocusOnTab: true
        maximumLength: box.maxLength
        onTextEdited: if (box.liveMs > 0) live.restart()
        Keys.onEscapePressed: event => {
            if (text === "") { event.accepted = false; return }
            text = ""
            live.stop()
            box.edited("")
            box.cleared()
        }
        Keys.onReturnPressed: box.submitted(text)
        Keys.onEnterPressed: box.submitted(text)
        Keys.onDownPressed: box.down()
        Accessible.role: Accessible.EditableText
        Accessible.name: box.placeholder
        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: field.text.length === 0
            text: box.placeholder
            color: Theme.dim
            font: field.font
            elide: Text.ElideRight
        }
    }
    Timer {
        id: live
        interval: Math.max(1, box.liveMs)
        onTriggered: box.edited(field.text)
    }
}
