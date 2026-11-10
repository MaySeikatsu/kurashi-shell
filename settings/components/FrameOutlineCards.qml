import QtQuick
import "../core"

// The frame outline's picker (SettingRow.picker; B79): each choice as a small picture of a frame's corner with a bar
// along its top, so the difference is seen before it is picked — no line, the line, the line lit, and Automatic as the
// chrome in effect gives it (`frame.outline_auto`, the daemon's: never a guess). Pictures in the theme's own colours;
// static. Keyboard as a radio group: Left/Right move, Space or Return picks; a click picks. It reads and sets its value
// itself: `rowKey` is bound by SettingRow, as every picker's is.
Item {
    id: cards
    property string rowKey: ""
    readonly property var row: { Store.schema; var h = Store.rowOf(cards.rowKey); return h ? h.row : ({}) }
    readonly property var provOf: { Store.config; return Store.prov(cards.rowKey, "") }
    readonly property var choices: cards.row.choices ?? []
    readonly property string current: String(cards.provOf === undefined ? cards.row.default : cards.provOf.value)
    // What a choice draws: "off" | "on" | "glow".
    function drawn(v: string): string {
        return v === "auto" ? String(Theme.tok("frame.outline_auto", "off")) : v
    }
    function label(c): string { return I18n.tr(c.label !== undefined ? String(c.label) : "config.choice.frame_outline." + c.value) }
    function value(c): string { return c.value !== undefined ? String(c.value) : String(c) }

    readonly property real cardW: Math.min(132, Math.floor((width - (choices.length - 1) * Theme.gap) / Math.max(1, choices.length)))
    implicitHeight: flow.implicitHeight
    height: implicitHeight
    objectName: "frame-outline:" + cards.rowKey
    Accessible.role: Accessible.RadioButton
    Accessible.name: cards.row.label ?? ""

    Row {
        id: flow
        spacing: Theme.gap
        Repeater {
            model: cards.choices
            delegate: Column {
                id: card
                required property var modelData
                required property int index
                readonly property string v: cards.value(modelData)
                readonly property string how: cards.drawn(v)
                readonly property bool on: v === cards.current
                spacing: 4
                width: cards.cardW
                Item {
                    id: pic
                    objectName: "frame-outline-card:" + card.v
                    width: parent.width
                    height: Math.round(width * 0.56)
                    activeFocusOnTab: card.on || (cards.current === "" && card.index === 0)
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: cards.label(card.modelData)
                    Accessible.checked: card.on
                    function pick(): void { if (Store.live) Store.setValue(cards.rowKey, card.v, "") }
                    Keys.onSpacePressed: event => { pick(); event.accepted = true }
                    Keys.onReturnPressed: event => { pick(); event.accepted = true }
                    Keys.onRightPressed: event => { cards.move(card.index, 1); event.accepted = true }
                    Keys.onLeftPressed: event => { cards.move(card.index, -1); event.accepted = true }
                    TapHandler { onTapped: { pic.forceActiveFocus(); pic.pick() } }
                    // The sheet (the frame and its bar), then the desktop inside it with the frame's inner corner.
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.rSm
                        color: Theme.surface
                        border.width: card.on ? 2 : 1
                        border.color: card.on ? Theme.accent : Theme.outline
                    }
                    Item {
                        id: hole
                        x: 9; y: 15
                        width: parent.width - x - 2
                        height: parent.height - y - 2
                        clip: true
                        Rectangle {
                            id: desk
                            width: parent.width + 14
                            height: parent.height + 14
                            radius: 9
                            color: Theme.color("color.surface_container_high", "#2f2c33")
                            border.width: card.how === "off" ? 0 : 1.5
                            border.color: card.how === "glow" ? Qt.alpha(Theme.frameGlowColor, 1) : (Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline)
                        }
                        // The light over the desktop: bands inside the line, fainter each (a picture, not the shell's pass).
                        Repeater {
                            model: card.how === "glow" ? 5 : 0
                            Rectangle {
                                required property int index
                                x: 1.5 + index * 1.6; y: x
                                width: desk.width - 2 * x
                                height: desk.height - 2 * y
                                radius: Math.max(0, desk.radius - x)
                                color: "transparent"
                                border.width: 1.8
                                border.color: Qt.alpha(Theme.frameGlowColor, 0.42 * Math.pow(0.62, index))
                            }
                        }
                    }
                    // A group on the bar, so the bar reads as one.
                    Rectangle {
                        x: 12; y: 4; width: 26; height: 7; radius: 3.5
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.outline
                    }
                    FocusRing { anchors.fill: parent; shown: pic.activeFocus; corner: Theme.rSm }
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: card.on ? Theme.fg : Theme.dim
                    font.pixelSize: Theme.fs - 2
                    font.weight: card.on ? Theme.wMedium : Theme.wRegular
                    font.family: Theme.fam(text, Theme.families)
                    text: cards.label(card.modelData)
                }
            }
        }
    }
    function move(from: int, by: int): void {
        var n = cards.choices.length
        if (n === 0) return
        var to = (from + by + n) % n
        if (Store.live) Store.setValue(cards.rowKey, cards.value(cards.choices[to]), "")
        var it = flow.children[to]
        if (it && it.children[0]) it.children[0].forceActiveFocus()
    }
}
