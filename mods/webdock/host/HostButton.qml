import QtQuick
import "core"

// A control of the web host's card: a 28 px glyph button for the header, or a text button (`label`, `primary`).
// The shell's kit (frontend/components IconButton, Button) is the same look; the host draws its own copy because it
// cannot import the components (they reach the core through "../core", a second copy of the singletons here).
// Reachable by Tab; Return, Enter and Space press it. The focus ring shows for keyboard focus only.
Rectangle {
    id: b

    property string glyph: ""
    property string label: ""
    property string a11y: ""
    property bool primary: false
    property bool enabled: true
    signal clicked()

    function press() {
        if (b.enabled) b.clicked()
    }

    readonly property bool texted: label !== ""
    implicitWidth: texted ? txt.implicitWidth + 2 * Theme.pad : 28
    implicitHeight: texted ? 28 : 28
    radius: texted ? Theme.rSm : Theme.rFull
    color: texted ? (primary ? Theme.accent : Theme.containerHigh)
        : (hover.hovered && enabled ? Theme.containerHigh : "transparent")
    opacity: enabled ? 1 : 0.5

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: b.press()
    Keys.onEnterPressed: b.press()
    Keys.onSpacePressed: b.press()
    Accessible.role: Accessible.Button
    Accessible.name: a11y !== "" ? a11y : label

    Text {
        id: txt
        anchors.centerIn: parent
        text: b.texted ? b.label : b.glyph
        color: b.texted && b.primary ? Theme.fgOnAccent : Theme.fg
        font.pixelSize: b.texted ? Theme.fsLabel : Theme.fs + 2
        font.family: Theme.fam(text, Theme.families)
    }
    HoverHandler {
        id: hover
    }
    MouseArea {
        anchors.fill: parent
        enabled: b.enabled
        onClicked: b.press()
    }
    Rectangle {
        anchors.fill: parent
        radius: b.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.focusRing
        visible: b.activeFocus
    }
}
