import QtQuick
import "../../core"
import ".."

// A key of the island's views (W21): a Block (a keycap under keycap chrome: it sinks onto its shadow while pressed and
// springs back) with an Icon, or a short label. `primary` takes the tonal `Theme.selected` fill (never the accent fill).
// Reachable by Tab; Return, Enter and Space press it. `a11y` is the translated accessible name.
Block {
    id: kb
    property string icon: ""
    property string glyph: ""
    property string label: ""
    property string a11y: ""
    property bool primary: false
    // `enabled` is Item's own: a disabled key takes no pointer and no focus.
    property int side: Theme.controlH + 4
    property int iconSize: Theme.fs + 8
    signal clicked()
    readonly property color onSel: Theme.fgOnSelected

    function press() { if (kb.enabled) kb.clicked() }

    implicitWidth: label !== "" ? txt.implicitWidth + 2 * Theme.pad + (icon !== "" || glyph !== "" ? ic.width + Theme.xs : 0) : side
    implicitHeight: side + Theme.shadowDy
    radius: label !== "" ? Theme.rFull : Math.min(Theme.rLg, side / 2)
    fill: primary ? Theme.selected : (hover.hovered && enabled ? Theme.containerHigh : Theme.container)
    flatBorder: primary ? "transparent" : Theme.outline
    pressed: tap.pressed && kb.enabled
    opacity: enabled ? 1 : 0.45

    activeFocusOnTab: kb.enabled
    Keys.onReturnPressed: kb.press()
    Keys.onEnterPressed: kb.press()
    Keys.onSpacePressed: kb.press()
    Accessible.role: Accessible.Button
    Accessible.name: kb.a11y !== "" ? kb.a11y : kb.label

    Row {
        anchors.centerIn: parent
        spacing: Theme.xs
        Icon {
            id: ic
            visible: kb.icon !== "" || kb.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: kb.icon
            glyph: kb.glyph
            filled: true
            size: kb.iconSize
            color: kb.primary ? kb.onSel : Theme.fg
        }
        Text {
            id: txt
            visible: kb.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            color: kb.primary ? kb.onSel : Theme.fg
            font.pixelSize: Theme.fs
            font.weight: Theme.wMedium
            font.family: Theme.fam(text, Theme.families)
            text: kb.label
        }
    }
    HoverHandler { id: hover; enabled: kb.enabled }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: kb.enabled
        onClicked: kb.clicked()
    }
    FocusRing {
        parent: kb.face
        anchors.fill: parent
        shown: kb.activeFocus
        corner: kb.radius
    }
}
