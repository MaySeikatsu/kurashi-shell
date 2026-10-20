import QtQuick
import "../core"

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

    function press() { if (b.enabled) b.clicked() }

    // Outlined chrome with no shadow of either kind draws its keys as boxes: the outline is the key, no fill.
    readonly property bool boxed: Theme.outlineW > 0 && Theme.shadowDy <= 0 && Theme.softR <= 0
    readonly property color base: primary ? Theme.accent
        : (boxed ? "transparent" : (Theme.groups ? Theme.container : Theme.containerHigh))
    implicitWidth: row.implicitWidth + 2 * Theme.pad + 2 * blk.inset
    implicitHeight: (Theme.ringW > 0 ? 34 : (Theme.groups ? 30 : 28)) + Theme.shadowDy
    opacity: enabled ? 1 : 0.5

    activeFocusOnTab: b.enabled
    Keys.onReturnPressed: b.press()
    Keys.onEnterPressed: b.press()
    Keys.onSpacePressed: b.press()
    Accessible.role: Accessible.Button
    Accessible.name: b.label

    Block {
        id: blk
        anchors.fill: parent
        radius: b.radius
        pressed: area.pressed && b.enabled
        fill: hover.hovered && b.enabled && Theme.groups ? (b.boxed && !b.primary ? Qt.alpha(Theme.fg, 0.08) : Qt.tint(b.base, Qt.alpha(Theme.fg, 0.08))) : b.base
        flatBorder: hover.hovered && b.enabled ? Theme.fg : "transparent"
        Row {
            id: row
            anchors.centerIn: parent
            spacing: Theme.xs + 2
            Icon {
                visible: b.icon !== "" && Theme.iconFamily !== ""
                name: b.icon
                size: Theme.fs + 3
                color: txt.color
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                id: txt
                anchors.verticalCenter: parent.verticalCenter
                // On the accent fill the text takes on_accent (4.5:1); on the container, the normal foreground.
                color: b.primary ? Theme.fgOnAccent : Theme.fg
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
