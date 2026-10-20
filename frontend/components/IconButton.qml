import QtQuick
import "../core"

// Glyph-only button, 28 px square; its hit area is the control height (32 px floor). `a11y` is the
// translated accessible name. Reachable by Tab; Return, Enter and Space press it. `icon` is a Material
// Symbols name drawn when the font is there; `glyph` is the text fallback (and the only mark without `icon`).
// Keycap chrome (K42): always a small round block that sinks while pressed; flat: a hover disc.
Item {
    id: b
    property string glyph: ""
    property string icon: ""
    property string a11y: ""
    property bool enabled: true
    // Lit: the button stands for something that is on (tonal fill).
    property bool lit: false
    property real radius: Theme.rFull
    signal clicked()

    function press() { if (b.enabled) b.clicked() }

    implicitWidth: Theme.keycap ? 32 : 28
    implicitHeight: (Theme.keycap ? 32 : 28) + Theme.shadowDy
    opacity: enabled ? 1 : 0.5

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: b.press()
    Keys.onEnterPressed: b.press()
    Keys.onSpacePressed: b.press()
    Accessible.role: Accessible.Button
    Accessible.name: b.a11y

    Block {
        id: blk
        anchors.fill: parent
        radius: b.radius
        ringScale: 0.34
        pressed: area.pressed && b.enabled
        fill: b.lit ? Theme.selected
            : (Theme.keycap ? (hover.hovered && b.enabled ? Theme.containerHigh : Theme.container)
                            : (hover.hovered && b.enabled ? Theme.containerHigh : "transparent"))
        Icon {
            anchors.centerIn: parent
            name: b.icon
            glyph: b.glyph
            filled: b.lit
            size: Theme.fs + 5
            color: b.lit ? Theme.onSelected : Theme.fg
        }
    }
    HoverHandler { id: hover }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -Math.max(0, (Theme.controlH - b.height) / 2)
        enabled: b.enabled
        onClicked: b.clicked()
    }
    FocusRing {
        width: blk.face.width
        height: blk.face.height
        y: blk.face.y
        shown: b.activeFocus
        corner: Math.min(b.radius, height / 2)
    }
}
