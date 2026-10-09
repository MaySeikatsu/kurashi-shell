import QtQuick
import "../../core"
import "../expanded"
import ".."

// Audio output in quick settings (K24, W12): the sinks svc.audio lists, the default one marked. A click,
// or Space or Return on a focused row, makes that sink the default (`audio.sink.default`); the row
// changes when the daemon's document does, not on the click. Without an audio server one dim line says
// so. Watches svc.audio only while the card is up (Ma).
Column {
    id: aud
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.audio" }
    readonly property var d: Store.docs["svc.audio"] || ({})
    readonly property bool avail: d.available === true
    readonly property var sinks: avail && d.sinks ? d.sinks : []
    property string errText: ""
    Refusal { id: refusal }

    function makeDefault(id) {
        aud.errText = ""
        Store.act("audio.sink.default", {id: id}, function (done, err) {
            if (err) aud.errText = refusal.text(err, "island.quick.audio.failed")
        })
    }

    // The rows are a ListModel updated in place: each change of the default brings a new sinks array, and a
    // Repeater over that array would rebuild the rows and drop the keyboard focus on the one just chosen.
    ListModel { id: rows }
    function syncRows() {
        var s = aud.sinks
        for (var i = 0; i < s.length; i++) {
            var r = {sinkId: s[i].id, sinkName: String(s[i].description || s[i].name || ""),
                     isDefault: s[i]["default"] === true}
            if (i < rows.count) rows.set(i, r)
            else rows.append(r)
        }
        while (rows.count > s.length) rows.remove(rows.count - 1)
    }
    onSinksChanged: syncRows()
    Component.onCompleted: syncRows()

    Text {
        visible: !aud.avail
        width: aud.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.unavailable")
    }
    Text {
        visible: aud.avail
        width: aud.width
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.heading")
    }
    Text {
        visible: aud.avail && aud.sinks.length === 0
        width: aud.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.audio.none")
    }
    Repeater {
        model: rows
        delegate: sinkRow
    }
    Text {
        visible: aud.errText !== ""
        width: aud.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: aud.errText
    }

    // One sink: a radio mark (the default has its dot and the word "Default", so the state is not colour
    // alone), the description, and a row of at least 32 px as the hit area and the Tab stop.
    Component {
        id: sinkRow
        Item {
            id: row
            required property int sinkId
            required property string sinkName
            required property bool isDefault
            width: aud.width
            height: Math.max(Theme.controlH, nameText.implicitHeight)
            activeFocusOnTab: true
            Keys.onSpacePressed: row.choose()
            Keys.onReturnPressed: row.choose()
            Keys.onEnterPressed: row.choose()
            Accessible.role: Accessible.RadioButton
            Accessible.name: row.sinkName
            Accessible.checked: row.isDefault

            function choose() { if (!row.isDefault) aud.makeDefault(row.sinkId) }

            Rectangle {
                id: mark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: "transparent"
                border.width: 2
                border.color: row.isDefault ? Theme.accent : Theme.dim
                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.accent
                    visible: row.isDefault
                }
            }
            Text {
                id: tag
                visible: row.isDefault
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("island.quick.audio.default")
            }
            Text {
                id: nameText
                x: mark.x + mark.width + Theme.gap
                width: row.width - x - (tag.visible ? tag.width + Theme.gap : 0)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: row.sinkName
            }
            FocusRing {
                anchors.fill: parent
                shown: row.activeFocus
                corner: Theme.rSm
            }
            MouseArea {
                anchors.fill: parent
                onClicked: row.choose()
            }
        }
    }
}
