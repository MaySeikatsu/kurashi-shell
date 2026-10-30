import QtQuick
import "../core"

// Under Light colour (K61): the light's colours as swatches, like the inks (InkSwatches) — natural, white, warm, cool and
// your own — each a pick, each in the colour the daemon resolves it to (`theme.appearance.light_colors`, row 340): natural
// is the mode's own light now (white, the sun's, the wallpaper's), marked "A" for automatic; your own is
// `theme.light.color_custom`, whose colour field is the row under this one. Keyboard as a radio group (arrows move,
// Return/Space pick); the selection is a ring and a check, never colour alone.
Column {
    id: ls
    readonly property string current: Store.valueOf("theme.light.color") || "natural"
    readonly property var names: ["natural", "white", "warm", "cool", "custom"]
    readonly property var colors: (Store.theme && Store.theme.appearance && Store.theme.appearance.light_colors) || ({})
    // A daemon without the colours (none yet): the light in effect for the picked one, a plain light for the others.
    function colorOf(n) {
        if (ls.colors[n] !== undefined) return ls.colors[n]
        return n === ls.current ? (Theme.tokens["light.color"] || "#ffffff") : "#ffffff"
    }
    function pick(n) { if (n !== ls.current && Store.live) Store.apply([{ set: "theme.light.color", value: n }]) }
    readonly property bool usable: {
        Store.config
        var h = Store.rowOf("theme.light.color")
        return Store.live && !(h && Store.inertReasons(h.row, "").some(function (x) {
            return x.kind !== "pending" && x.kind !== "unavailable" && x.kind !== "mod_off" }))
    }

    width: parent ? parent.width : 480
    spacing: Theme.gap
    objectName: "light-swatches"
    opacity: ls.usable ? 1 : 0.5

    Row {
        spacing: Theme.pad
        Repeater {
            id: rep
            model: ls.names
            delegate: Item {
                id: sw
                required property string modelData
                required property int index
                readonly property bool on: modelData === ls.current
                objectName: "light:" + modelData
                width: Math.max(44, cap.implicitWidth)
                height: 30 + 4 + cap.height
                activeFocusOnTab: sw.on && ls.usable
                Keys.onLeftPressed: event => { var c = rep.itemAt(sw.index - 1); if (c) c.forceActiveFocus(); event.accepted = true }
                Keys.onRightPressed: event => { var c = rep.itemAt(sw.index + 1); if (c) c.forceActiveFocus(); event.accepted = true }
                Keys.onReturnPressed: event => { ls.pick(modelData); event.accepted = true }
                Keys.onEnterPressed: event => { ls.pick(modelData); event.accepted = true }
                Keys.onSpacePressed: event => { ls.pick(modelData); event.accepted = true }
                Accessible.role: Accessible.RadioButton
                Accessible.name: I18n.tr("config.choice.light_color." + modelData)
                Accessible.checked: sw.on
                Rectangle {
                    id: dot
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 30
                    height: 30
                    radius: 15
                    // A little lit sphere: the colour, brighter toward the top left.
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(ls.colorOf(sw.modelData), 1.08) }
                        GradientStop { position: 1; color: Qt.darker(ls.colorOf(sw.modelData), 1.12) }
                    }
                    border.width: sw.on ? 2 : 1
                    border.color: sw.on ? Theme.accent : Theme.outline
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        anchors.centerIn: parent
                        visible: sw.on || sw.modelData === "natural" || sw.modelData === "custom"
                        color: "#3a3530"
                        font.pixelSize: 13
                        font.bold: true
                        text: sw.on ? "✓" : (sw.modelData === "natural" ? "A" : "+")
                    }
                }
                Text {
                    id: cap
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    anchors.top: dot.bottom
                    anchors.topMargin: 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: sw.on ? Theme.fg : Theme.dim
                    font.pixelSize: Theme.fs - 2
                    font.weight: sw.on ? Font.Bold : Font.Normal
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("config.choice.light_color." + sw.modelData)
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: Store.live && ls.usable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ls.pick(sw.modelData)
                }
                FocusRing {
                    anchors.fill: dot
                    anchors.margins: -2
                    shown: sw.activeFocus
                    corner: width / 2
                }
            }
        }
    }
}
