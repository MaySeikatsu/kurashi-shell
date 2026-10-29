import QtQuick
import "../core"

// Text button. `label` is already translated by the caller. Emits `clicked` only. Reachable by Tab;
// Return, Enter and Space press it. A click does not take focus, so the ring shows for keyboard users only.
RoundBox {
    id: b
    property string label: ""
    // The name a screen reader says, when the visible label is a glyph ("↑") that says nothing by itself.
    property string accessibleName: ""
    property bool primary: false
    property bool enabled: true
    signal clicked()

    function press() { if (b.enabled) b.clicked() }

    implicitWidth: txt.implicitWidth + 2 * Theme.pad
    implicitHeight: Theme.controlH
    radius: Theme.keycap ? height / 2 : Theme.rSm
    color: primary ? Theme.accent : Theme.containerHigh
    opacity: enabled ? 1 : 0.5
    // Keycap chrome (K42): ink outline and a hard shadow below (a child behind the button).
    border.width: Theme.outlineW > 0 ? Theme.outlineW : (hover.hovered && enabled ? 1 : 0)
    border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.fg
    // Keycap chrome: the hard shadow along the shadow vector (K67). Pressed, it stands 1 px off the face along each axis
    // (the sign of the step: straight down at the defaults, as before), so the key reads as sunk onto it.
    RoundBox {
        z: -1
        visible: Theme.sinkX !== 0 || Theme.sinkY !== 0
        x: area.pressed ? Math.sign(Theme.sinkX) : Theme.sinkX
        y: area.pressed ? Math.sign(Theme.sinkY) : Theme.sinkY
        width: b.width
        height: b.height
        radius: b.radius
        color: Theme.line
    }

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: event => { b.press(); event.accepted = true }
    Keys.onEnterPressed: event => { b.press(); event.accepted = true }
    Keys.onSpacePressed: event => { b.press(); event.accepted = true }
    Accessible.role: Accessible.Button
    Accessible.name: b.accessibleName !== "" ? b.accessibleName : b.label

    Text {
        id: txt
        anchors.centerIn: parent
        // On the accent fill the text takes on_accent (4.5:1); on the container, the normal foreground.
        color: b.primary ? Theme.fgOnAccent : Theme.fg
        font.pixelSize: Theme.fs
        font.weight: Theme.wMedium
        font.family: Theme.fam(text, Theme.families)
        text: b.label
    }
    HoverHandler { id: hover }
    MouseArea {
        id: area
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
