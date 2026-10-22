import QtQuick
import "../core"

// Under Text colour (K60): the inks as swatches in the scheme in effect (`theme.appearance.inks`, the daemon's shades;
// "The palette's" shows the palette's own text colour), each a pick, and a sample line in the colour in effect. The
// selection is a ring and a check, never colour alone; keyboard as a radio group (arrows move, Return/Space pick).
Column {
    id: ik
    readonly property var inks: (Store.theme && Store.theme.appearance && Store.theme.appearance.inks) || ({})
    readonly property string current: Store.valueOf("theme.colors.ink") || "palette"
    // Every ink the row offers (the swatches are the row's only picker, so none may be missing): "Your own" shows
    // `theme.colors.ink_custom`, the colour the daemon uses for it; its colour field is the row under this one.
    readonly property var names: {
        Store.schema
        var h = Store.rowOf("theme.colors.ink")
        var c = h && h.row.choices ? h.row.choices.map(function (x) { return x.value }) : []
        return c.length ? c : ["palette", "blue", "black", "sepia", "red", "green", "violet", "custom"]
    }
    function colorOf(n) {
        if (n === "palette") return Theme.color("color.on_surface", "#888888")
        if (n === "custom") return Store.valueOf("theme.colors.ink_custom") || "#888888"
        return ik.inks[n] || "#888888"
    }
    function pick(n) { if (n !== ik.current && Store.live) Store.apply([{ set: "theme.colors.ink", value: n }]) }

    width: parent ? parent.width : 480
    spacing: Theme.gap
    objectName: "ink-swatches"

    Row {
        spacing: Theme.pad
        Repeater {
            id: rep
            model: ik.names
            delegate: Item {
                id: sw
                required property string modelData
                required property int index
                readonly property bool on: modelData === ik.current
                objectName: "ink:" + modelData
                // Each with its name under it: the swatches are the row's picker, so the names must be on screen.
                width: Math.max(40, cap.implicitWidth)
                height: 30 + 4 + cap.height
                activeFocusOnTab: sw.on
                Keys.onLeftPressed: event => { var c = rep.itemAt(sw.index - 1); if (c) c.forceActiveFocus(); event.accepted = true }
                Keys.onRightPressed: event => { var c = rep.itemAt(sw.index + 1); if (c) c.forceActiveFocus(); event.accepted = true }
                Keys.onReturnPressed: event => { ik.pick(modelData); event.accepted = true }
                Keys.onEnterPressed: event => { ik.pick(modelData); event.accepted = true }
                Keys.onSpacePressed: event => { ik.pick(modelData); event.accepted = true }
                Accessible.role: Accessible.RadioButton
                Accessible.name: I18n.tr("config.choice.ink." + modelData)
                Accessible.checked: sw.on
                Text {
                    id: cap
                    anchors.top: dot.bottom
                    anchors.topMargin: 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: sw.on ? Theme.fg : Theme.dim
                    font.pixelSize: Theme.fs - 2
                    font.weight: sw.on ? Font.Bold : Font.Normal
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("config.choice.ink." + sw.modelData)
                }
                Rectangle {
                    id: dot
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 2
                    width: 26
                    height: 26
                    radius: 13
                    color: ik.colorOf(sw.modelData)
                    border.width: sw.on ? 2 : 1
                    border.color: sw.on ? Theme.accent : Theme.outline
                    Text {
                        anchors.centerIn: parent
                        visible: sw.on || sw.modelData === "palette" || sw.modelData === "custom"
                        color: Theme.surface
                        font.pixelSize: 13
                        font.bold: true
                        text: sw.on ? "✓" : (sw.modelData === "custom" ? "+" : "P")
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: Store.live
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ik.pick(sw.modelData)
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
    // A Latin and a Japanese sample, each in its own family (one Text takes one family).
    Row {
        spacing: Theme.pad
        Repeater {
            model: I18n.tr("settings.ink.sample").split(" · ")
            delegate: Text {
                required property string modelData
                color: Theme.fg
                font.pixelSize: Theme.fs + 1
                font.family: Theme.fam(modelData, Theme.families)
                text: modelData
            }
        }
    }
}
