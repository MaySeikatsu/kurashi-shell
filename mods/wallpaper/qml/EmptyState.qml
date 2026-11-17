import QtQuick
import qs.core
import qs.components

// What stands in place of the grid (docs/ux/wallpaper.md "States"): loading, no backend, no folder, a missing folder, an
// empty library, no looks, nothing matching — each says what to do next, with the one button that does it (restart the
// backend, show every picture again).
Column {
    id: es
    required property var host
    property bool large: true
    spacing: Theme.gap
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Theme.fg
        font.pixelSize: es.large ? Theme.fsTitle : Theme.fs
        font.weight: es.large ? Theme.wRegular : Theme.wMedium
        font.family: Theme.fam(text, Theme.families)
        text: es.host.emptyTitle()
    }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Theme.dim
        visible: text !== ""
        font.pixelSize: es.large ? Theme.fsLabel : Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: es.host.emptyHint()
    }
    Button {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: es.host.loaded && es.host.installed && !es.host.backendUp
        label: I18n.tr("mod-wallpaper.backend.restart")
        onClicked: es.host.restartBackend()
    }
    Button {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: es.host.loaded && es.host.installed && es.host.onlyLooks
        label: I18n.tr("mod-wallpaper.favourites.all")
        onClicked: es.host.onlyLooks = false
    }
}
