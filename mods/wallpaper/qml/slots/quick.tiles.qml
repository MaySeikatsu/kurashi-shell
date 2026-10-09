import QtQuick
import "../../../../frontend/core"
import "../../../../frontend/components"

// The wallpaper tile in quick settings (K28 slot `quick.tiles`): what the rotation is doing, and its
// three one-step actions. The slot shows it only while the daemon says the mod is available; the tile
// subscribes to `mod.wallpaper` for its own line, and that subscription is all it does.
Item {
    id: tile
    implicitWidth: 240
    implicitHeight: 88

    Watch { doc: "mod.wallpaper" }
    readonly property var doc: Store.docs["mod.wallpaper"] || ({})
    readonly property var rotationState: doc.rotation || ({})
    readonly property bool paused: rotationState.paused === true
    readonly property bool up: doc.available === true && (doc.backend || ({})).available === true

    function act(action, args) {
        Store.act(action, args || {}, function () {})
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rLg
        color: Theme.container
        border.width: 1
        border.color: Theme.outline

        Column {
            anchors.fill: parent
            anchors.margins: Theme.pad
            spacing: Theme.xs
            Text {
                width: parent.width
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("mod-wallpaper.tile.title")
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                color: tile.up ? Theme.dim : Theme.error
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: {
                    if (!tile.up) return I18n.tr((tile.doc.backend || ({})).reason || "mod-wallpaper.backend.down")
                    if (tile.rotationState.on === true)
                        return I18n.tr("mod-wallpaper.tile.rotating").split("{min}").join(String(tile.rotationState.interval_min))
                    return I18n.tr(tile.paused ? "mod-wallpaper.rotation.paused" : "mod-wallpaper.rotation.off")
                }
            }
            Row {
                spacing: Theme.xs
                Button {
                    label: I18n.tr("mod-wallpaper.tile.next")
                    enabled: tile.up
                    onClicked: tile.act("wallpaper.next")
                }
                Button {
                    label: I18n.tr("mod-wallpaper.tile.random")
                    enabled: tile.up
                    onClicked: tile.act("wallpaper.random")
                }
                Button {
                    label: I18n.tr(tile.paused ? "mod-wallpaper.tile.resume" : "mod-wallpaper.tile.pause")
                    enabled: tile.up && (tile.rotationState.interval_min || 0) > 0
                    onClicked: tile.act("wallpaper.rotation.pause", { on: !tile.paused })
                }
            }
        }
    }
}
