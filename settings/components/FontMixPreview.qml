import QtQml
import QtQuick
import "../core"

// Settings › Fonts (K93, docs/ux/fonts.md): the comparison. One font, then the mix of two, three … of the fonts in the list, each in
// its own row, so the choice is made by looking at it. The mixes are real ones: `font.mix.preview` builds each once. Static at rest.
SectionCard {
    id: mp
    objectName: "font-mix-preview"
    title: I18n.tr("fonts.preview.title")
    function value(k, d) { var v = Store.valueOf(k); return v === undefined || v === null ? d : v }
    readonly property string preset: String(value("theme.typography.mix.preset", "off"))
    readonly property int count: Number(value("theme.typography.mix.count", 3))
    readonly property var handwriting: ["Kalam", "Patrick Hand", "Handlee", "Gochi Hand"]
    readonly property var list: preset === "custom" ? value("theme.typography.mix.fonts", []) : handwriting
    readonly property string state_: String(Theme.tok("font.mix.state", "off"))
    readonly property var missing: Theme.tok("font.mix.missing", [])
    readonly property var samples: [I18n.tr("fonts.preview.sample1"), I18n.tr("fonts.preview.sample2"), I18n.tr("fonts.preview.sample3")]
    // The rows: one font alone, then 2 … the list's length.
    readonly property var rows: {
        var n = Math.min(4, list.length), out = []
        for (var i = 1; i <= n; i++) out.push(list.slice(0, i))
        return out
    }
    Column {
        width: parent ? parent.width : 0
        spacing: Theme.gap
        // K102: your own hand among the fonts, when the mod that makes it is on; a way to it when it is off.
        Row {
            readonly property var hand: Store.modEntry("handwriting")
            readonly property bool on: !!hand && hand.state === "enabled"
            visible: !!hand
            width: parent.width
            spacing: Theme.gap
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - drawKey.width - parent.spacing
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr(parent.on ? "fonts.hand.on" : "fonts.hand.off")
            }
            Button {
                id: drawKey
                objectName: "fonts-draw"
                anchors.verticalCenter: parent.verticalCenter
                label: I18n.tr(parent.on ? "fonts.hand.open" : "fonts.hand.enable")
                enabled: Store.live
                onClicked: parent.on ? Store.act("mod.panel.open", { id: "handwriting", panel: "handwriting" })
                                     : Store.act("mod.enable", { id: "handwriting" })
            }
        }
        Text {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: mp.state_ === "building" ? I18n.tr("fonts.preview.building")
                : mp.state_ === "too_few" ? I18n.tr("fonts.preview.too_few")
                : mp.state_ === "failed" ? I18n.tr("fonts.preview.failed")
                : mp.missing.length > 0 ? I18n.tr("fonts.preview.missing").replace("{names}", mp.missing.join(", ")) : ""
        }
        Repeater {
            model: mp.rows
            Column {
                id: rowItem
                required property var modelData
                required property int index
                objectName: "font-mix-row:" + modelData.length
                width: parent.width
                spacing: 2
                property string family: modelData.length === 1 ? String(modelData[0]) : ""
                property string file: ""
                Instantiator {
                    id: load
                    model: rowItem.file !== "" ? 1 : 0
                    delegate: FontLoader { source: "file://" + rowItem.file }
                }
                Component.onCompleted: ask()
                onModelDataChanged: ask()
                function ask() {
                    if (modelData.length < 2) { file = ""; family = String(modelData[0]); return }
                    Store.act("font.mix.preview", { fonts: modelData }, function (m) {
                        rowItem.file = m && m.data && m.data.file ? m.data.file : ""
                    })
                }
                readonly property string shown: file !== "" ? (load.object && load.object.status === FontLoader.Ready ? load.object.name : "") : family
                readonly property bool inEffect: mp.preset !== "off" && modelData.length === Math.min(mp.count, mp.list.length)
                Text {
                    color: rowItem.inEffect ? Theme.accent : Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.weight: rowItem.inEffect ? Theme.wBold : Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                    readonly property string label: (rowItem.modelData.length === 1 ? I18n.tr("fonts.preview.one")
                        : I18n.tr("fonts.preview.many").replace("{n}", rowItem.modelData.length)) + ": " + rowItem.modelData.join(" + ")
                    text: rowItem.inEffect ? I18n.tr("fonts.preview.current").replace("{label}", label) : label
                }
                Repeater {
                    model: rowItem.shown !== "" ? mp.samples : []
                    Text {
                        required property string modelData
                        width: rowItem.width
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fs + 4
                        font.family: rowItem.shown
                        text: modelData
                    }
                }
            }
        }
    }
}
