import QtQuick
import "../core"

// Under Text colour (K60): the inks as swatches in the scheme in effect (`theme.appearance.inks`, the daemon's shades;
// "The palette's" shows the palette's own text colour), each a pick, and a sample line in the colour in effect. The
// selection is a ring and a check, never colour alone; keyboard as a radio group (arrows move, Return/Space pick).
Column {
    id: ik
    readonly property var inks: (Store.theme && Store.theme.appearance && Store.theme.appearance.inks) || ({})
    readonly property string current: Store.valueOf("theme.colors.ink") || "palette"
    readonly property var names: ["palette", "blue", "black", "sepia", "red", "green", "violet"]
    function colorOf(n) { return n === "palette" ? Theme.color("color.on_surface", "#888888") : (ik.inks[n] || "#888888") }
    function pick(n) { if (n !== ik.current && Store.live) Store.apply([{ set: "theme.colors.ink", value: n }]) }

    width: parent ? parent.width : 480
    spacing: Theme.gap
    objectName: "ink-swatches"

    Row {
        spacing: Theme.gap
        Repeater {
            id: rep
            model: ik.names
            delegate: Item {
                id: sw
                required property string modelData
                required property int index
                readonly property bool on: modelData === ik.current
                objectName: "ink:" + modelData
                width: 30
                height: 30
                activeFocusOnTab: sw.on
                Keys.onLeftPressed: event => { var c = rep.itemAt(sw.index - 1); if (c) c.forceActiveFocus(); event.accepted = true }
                Keys.onRightPressed: event => { var c = rep.itemAt(sw.index + 1); if (c) c.forceActiveFocus(); event.accepted = true }
                Keys.onReturnPressed: event => { ik.pick(modelData); event.accepted = true }
                Keys.onSpacePressed: event => { ik.pick(modelData); event.accepted = true }
                Accessible.role: Accessible.RadioButton
                Accessible.name: I18n.tr("config.choice.ink." + modelData)
                Accessible.checked: sw.on
                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: 13
                    color: ik.colorOf(sw.modelData)
                    border.width: sw.on ? 2 : 1
                    border.color: sw.on ? Theme.accent : Theme.outline
                    Text {
                        anchors.centerIn: parent
                        visible: sw.on || sw.modelData === "palette"
                        color: Theme.surface
                        font.pixelSize: 13
                        font.bold: true
                        text: sw.on ? "✓" : "P"
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: Store.live
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ik.pick(sw.modelData)
                }
                FocusRing {
                    anchors.fill: parent
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
