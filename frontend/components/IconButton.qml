import QtQuick
import "../core"

// Glyph-only button; `a11y` is the translated accessible name (shown nowhere yet, kept for the
// accessibility pass).
Rectangle {
    id: b
    property string glyph: ""
    property string a11y: ""
    property bool enabled: true
    signal clicked()

    implicitWidth: 28
    implicitHeight: 28
    radius: Theme.rFull
    color: hover.hovered && enabled ? Theme.containerHigh : "transparent"
    opacity: enabled ? 1 : 0.5

    Text {
        anchors.centerIn: parent
        color: Theme.fg
        font.pixelSize: Theme.fs + 2
        font.family: Theme.fam(text, Theme.families)
        text: b.glyph
    }
    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        enabled: b.enabled
        onClicked: b.clicked()
    }
}
