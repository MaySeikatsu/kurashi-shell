import QtQuick
import "../../core"
import "../expanded"
import ".."

// The media mini row (docs/ux/quick-settings.md, Design 6): one row while something plays. Its title opens the island's
// media view (`island.expand`); the transport sends the media actions. `d` is svc.media, read by QuickPanel (Ma).
Column {
    id: mini
    property var d: ({})
    property string errText: ""
    signal openRequested()
    spacing: Theme.xs
    Refusal { id: refusal }

    function transport(action) {
        mini.errText = ""
        Store.act(action, {}, function (done, err) {
            if (err) mini.errText = refusal.text(err, "island.media.failed")
        })
    }

    Row {
        width: mini.width
        spacing: Theme.gap
        Item {
            id: titleZone
            width: mini.width - controls.width - Theme.gap
            height: Math.max(Theme.controlH, names.implicitHeight)
            activeFocusOnTab: true
            Keys.onReturnPressed: mini.openRequested()
            Keys.onEnterPressed: mini.openRequested()
            Keys.onSpacePressed: mini.openRequested()
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("island.quick.media.open")
            Accessible.description: mini.d.title !== undefined ? String(mini.d.title) : ""

            Column {
                id: names
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: String(mini.d.title ?? "")
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    width: parent.width
                    visible: text !== ""
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: String(mini.d.artist ?? "")
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: mini.openRequested()
            }
            FocusRing {
                anchors.fill: parent
                shown: titleZone.activeFocus
                corner: Theme.rSm
            }
        }
        Row {
            id: controls
            spacing: 2
            IconButton {
                glyph: "⏮"
                a11y: I18n.tr("island.media.prev")
                onClicked: mini.transport("media.prev")
            }
            IconButton {
                glyph: mini.d.playing === true ? "⏸" : "▶"
                a11y: mini.d.playing === true ? I18n.tr("island.media.pause") : I18n.tr("island.media.play")
                onClicked: mini.transport("media.play_pause")
            }
            IconButton {
                glyph: "⏭"
                a11y: I18n.tr("island.media.next")
                onClicked: mini.transport("media.next")
            }
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: mini.errText !== ""
        width: mini.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: mini.errText
    }
}
