import QtQuick
import "../core"

// Glyph-only button, 28 px square; its hit area is the control height (32 px floor). `a11y` is the
// translated accessible name. Reachable by Tab; Return, Enter and Space press it.
Rectangle {
    id: b
    property string glyph: ""
    property string a11y: ""
    property bool enabled: true
    signal clicked()

    function press() { if (b.enabled) b.clicked() }

    implicitWidth: 28
    implicitHeight: 28
    radius: Theme.rFull
    color: hover.hovered && enabled ? Theme.containerHigh : "transparent"
    opacity: enabled ? 1 : 0.5

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: b.press()
    Keys.onEnterPressed: b.press()
    Keys.onSpacePressed: b.press()
    Accessible.role: Accessible.Button
    Accessible.name: b.a11y

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
        // The hit area grows to the control height (32 px floor); the drawn glyph button keeps its size.
        anchors.margins: -Math.max(0, (Theme.controlH - b.height) / 2)
        enabled: b.enabled
        onClicked: b.clicked()
    }
    FocusRing {
        anchors.fill: parent
        shown: b.activeFocus
        corner: b.radius
    }
}
