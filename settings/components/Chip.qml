import QtQuick
import "../core"

// Small pill label. Purely presentational.
Rectangle {
    id: c
    property string text: ""
    property color fg: Theme.dim
    property color bg: Theme.surface
    property color edge: Theme.outline

    implicitWidth: t.implicitWidth + Theme.gap * 1.5
    implicitHeight: t.implicitHeight + 4
    radius: Theme.rFull
    color: bg
    border.width: 1
    border.color: edge

    Text {
        id: t
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        anchors.centerIn: parent
        color: c.fg
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: c.text
    }
}
