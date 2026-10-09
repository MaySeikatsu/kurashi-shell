import QtQuick
import "../../core"
import ".."

// The expanded view of the media face (K24): art decoded at display size, title and artist from
// svc.media, and the transport. Watches svc.media only while it is on screen (Ma). No player (or no
// title) reads as nothing playing, and the transport is off: there is nothing to act on. Mod
// contributions (K28): `backdrop` behind the content (decorative; a contribution gates its own motion),
// `below` under the transport (lyrics).
Item {
    id: view
    width: parent.width
    implicitHeight: col.implicitHeight

    Watch { doc: "svc.media" }
    readonly property var d: Store.docs["svc.media"] || ({})
    readonly property bool idle: d.available === false || (d.title ?? "") === ""
    readonly property bool playing: !idle && d.playing === true
    property string errText: ""
    Refusal { id: refusal }

    function transport(action) {
        errText = ""
        Store.act(action, {}, function (done, err) {
            if (err) view.errText = refusal.text(err, "island.media.failed")
        })
    }

    SlotHost { anchors.fill: parent; layout: "stack"; slot: "media.expanded.backdrop"; z: -1 }
    Column {
        id: col
        width: view.width
        spacing: Theme.gap

        Text {
            width: view.width
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.media.heading")
        }
        Row {
            width: view.width
            spacing: Theme.gap
            Image {
                id: art
                visible: !view.idle && (view.d.art_url ?? "") !== "" && status === Image.Ready
                width: visible ? 56 : 0
                height: 56
                // Decoded at display size (2x for a sharp edge), not at the cover's own size.
                sourceSize: Qt.size(112, 112)
                source: view.idle ? "" : (view.d.art_url ?? "")
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
            }
            Column {
                width: view.width - art.width - (art.visible ? Theme.gap : 0)
                spacing: Theme.xs
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    color: view.idle ? Theme.dim : Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: view.idle ? I18n.tr("island.media.idle") : (view.d.title ?? "")
                }
                Text {
                    visible: !view.idle && (view.d.artist ?? "") !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: view.d.artist ?? ""
                }
            }
        }

        Item {
            width: view.width
            height: Theme.controlH
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.gap
                IconButton {
                    glyph: "⏮"
                    a11y: I18n.tr("island.media.prev")
                    enabled: !view.idle
                    onClicked: view.transport("media.prev")
                }
                IconButton {
                    glyph: view.playing ? "⏸" : "▶"
                    a11y: I18n.tr(view.playing ? "island.media.pause" : "island.media.play")
                    enabled: !view.idle
                    onClicked: view.transport("media.play_pause")
                }
                IconButton {
                    glyph: "⏭"
                    a11y: I18n.tr("island.media.next")
                    enabled: !view.idle
                    onClicked: view.transport("media.next")
                }
            }
        }
        SlotHost { slot: "media.expanded.below"; width: view.width }
        Text {
            visible: view.errText !== ""
            width: view.width
            wrapMode: Text.WordWrap
            color: Theme.error
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: view.errText
        }
    }
}
