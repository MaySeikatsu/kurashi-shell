import QtQuick
import Quickshell
import "../core"
import "decor"

// Text button. `label` is already translated by the caller (I18n.tr). Emits `clicked`; the caller
// decides which action/intent that means. Reachable by Tab; Return, Enter and Space press it.
// Drawn as a Block (K42, K45): a flat fill, a keycap that sinks while pressed, a soft pill that shrinks, or (line chrome:
// an outline with no shadow) an outlined box with no fill behind its text. `icon` (a Material Symbols name) puts an icon
// before the label.
Item {
    id: b
    property string label: ""
    property string icon: ""
    property bool primary: false
    property bool enabled: true
    property real radius: Theme.groups ? Theme.rFull : Theme.rSm
    signal clicked()
    // K61 (docs/ux/texture.md "Controls"): an opaque face carries the relief over its fill and icon, under its label (Block's
    // own is then left out: one relief per pixel), in a window that shares its sheet. A boxed (line chrome) button has no
    // fill at rest and gets none (QuickButton).
    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property bool ownRelief: Theme.texControls && !Theme.texText && blk.fill.a >= 1 && !!(qsw && qsw.tileSheet)

    function press() { if (b.enabled) b.clicked() }

    // Outlined chrome with no shadow of either kind draws its keys as boxes: the outline is the key, no fill.
    readonly property bool boxed: Theme.outlineW > 0 && Theme.shadowDy <= 0 && Theme.softR <= 0
    readonly property color base: primary ? Theme.accent
        : (boxed ? "transparent" : (Theme.groups ? Theme.container : Theme.containerHigh))
    implicitWidth: row.implicitWidth + 2 * Theme.pad + 2 * blk.inset
    implicitHeight: (Theme.ringW > 0 ? 34 : (Theme.groups ? 30 : 28)) + Theme.shadowDy
    opacity: enabled ? 1 : 0.5

    // I196: a button in a row of card keys (the desk's edit mode) passes Return on to its card (`acceptsReturn: false`),
    // where it means Done; Enter and Space still press it. Default unchanged everywhere else.
    property bool acceptsReturn: true
    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: event => { if (b.acceptsReturn) b.press(); else event.accepted = false }
    Keys.onEnterPressed: event => { if (b.acceptsReturn) b.press(); else event.accepted = false }
    Keys.onSpacePressed: b.press()
    Accessible.role: Accessible.Button
    Accessible.name: b.label

    // W53.4 (contract row 604): the look's push-button face (`[slots] button`, contract decor/button/ButtonBase.qml: XP's
    // and 7's glossy and glass buttons, Aqua's gel) under the content; the Block then draws only the content (`bare`).
    // Without the slot nothing is made and the Block is the button, as before.
    DecorHost {
        id: part
        slot: "button"
        anchors.fill: parent
        onLoaded: {
            item.pressed = Qt.binding(function () { return area.pressed && b.enabled })
            item.hovered = Qt.binding(function () { return hover.hovered && b.enabled })
            item.primary = Qt.binding(function () { return b.primary })
        }
    }
    readonly property bool parted: part.ready
    Block {
        id: blk
        anchors.fill: parent
        radius: b.radius
        bare: b.parted
        pressed: area.pressed && b.enabled
        fill: hover.hovered && b.enabled && Theme.groups ? (b.boxed && !b.primary ? Qt.alpha(Theme.fg, 0.08) : Qt.tint(b.base, Qt.alpha(Theme.fg, 0.08))) : b.base
        flatBorder: hover.hovered && b.enabled ? Theme.fg : "transparent"
        relief: !b.ownRelief
        // The icon lies under the relief and the label over it (K61): the icon is drawn here, at the row's slot for it.
        Icon {
            id: lead
            visible: b.icon !== "" && Theme.iconFamily !== ""
            name: b.icon
            size: Theme.fs + 3
            color: txt.color
            x: row.x + slot.x
            y: row.y + (row.height - height) / 2
        }
        Loader {
            active: b.ownRelief
            anchors.fill: parent
            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, Math.min(blk.radius, blk.face.height / 2) - blk.inset) }
        }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.xs + 2
            Item {
                id: slot
                visible: lead.visible
                width: lead.implicitWidth
                height: lead.implicitHeight
            }
            Text {
                id: txt
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                anchors.verticalCenter: parent.verticalCenter
                // On the accent fill the text takes on_accent (4.5:1); on the container, the normal foreground.
                color: b.parted && part.item.ink.a > 0 ? part.item.ink : b.primary ? Theme.fgOnAccent : Theme.fg
                font.pixelSize: Theme.fs
                font.weight: Theme.wMedium
                font.family: Theme.fam(text, Theme.families)
                text: b.label
            }
        }
    }
    HoverHandler { id: hover }
    MouseArea {
        id: area
        anchors.fill: parent
        // The hit area grows to the control height (32 px floor); the drawn button keeps its size.
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
        stroke: b.primary && Theme.ringW <= 0 ? Theme.fgOnAccent : Theme.focusRing
    }
}
