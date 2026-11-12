import QtQuick
import qs.core
import qs.components

// A pin's menu (docs/ux/webdock.md "Keyboard and a11y"): move the pin up or down in the strip, or remove it, opened by a
// right click or the menu key on its tile. A pin the configuration sets (`forced_by`) shows who sets it, and its edits
// are inert (provenance, rule 2): the buttons are disabled, never hidden.
// W76 ("Round three"): after the edits, a site's page entries — Reload (the loaded page), Update pin to this page (where the page is
// now, `at`, the host's report), Unpin but keep open (the row goes, the page stays until the dock's rules unload it). An
// entry that cannot act says why in its description (not loaded, at home, set by the configuration).
Rectangle {
    id: menu
    property var pin: ({})
    property int index: 0
    property int count: 0
    readonly property bool forced: pin.forced_by !== undefined && pin.forced_by !== null
    signal moved(int to)
    signal removed()
    signal closed()
    signal reloaded()
    signal retargeted()
    signal unpinned()
    readonly property bool site: pin.kind === "web"
    readonly property bool loaded: pin.loaded === true
    readonly property bool away: site && pin.at !== undefined && pin.at !== null && String(pin.at) !== ""

    radius: Theme.rLg
    color: Theme.container
    activeFocusOnTab: true
    Keys.onEscapePressed: menu.closed()
    // The menu takes the keyboard when it opens: the first button that is enabled has the focus.
    Component.onCompleted: Qt.callLater(function () {
        var first = [moveUp, moveDown, removeBtn, reloadBtn, retargetBtn, unpinBtn, closeBtn]
            .filter(function (b) { return b.visible && b.enabled })
        if (first.length > 0) first[0].forceActiveFocus()
    })

    Column {
        anchors.fill: parent
        anchors.margins: Theme.pad
        spacing: Theme.gap

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: String(menu.pin.title || menu.pin.id || "")
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
        }
        // W73: a pin that keeps running in the background says so here too (it costs memory and power while hidden).
        Text {
            visible: menu.pin.background === true && menu.pin.kind !== "view"
            width: parent.width
            wrapMode: Text.WordWrap
            text: I18n.tr("webdock.pin.background")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Text {
            visible: menu.forced
            width: parent.width
            wrapMode: Text.WordWrap
            text: I18n.tr("webdock.dock.forced") + " " + String(menu.pin.forced_by || "")
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
        }
        Button {
            id: moveUp
            label: I18n.tr("webdock.dock.move_up")
            enabled: !menu.forced && menu.index > 0
            onClicked: menu.moved(menu.index - 1)
        }
        Button {
            id: moveDown
            label: I18n.tr("webdock.dock.move_down")
            enabled: !menu.forced && menu.index < menu.count - 1
            onClicked: menu.moved(menu.index + 1)
        }
        Button {
            id: removeBtn
            label: I18n.tr("webdock.dock.remove")
            enabled: !menu.forced
            onClicked: menu.removed()
        }
        Button {
            id: reloadBtn
            visible: menu.site
            label: I18n.tr("webdock.menu.reload")
            enabled: menu.loaded
            Accessible.description: menu.loaded ? "" : I18n.tr("webdock.menu.not_loaded")
            onClicked: menu.reloaded()
        }
        Button {
            id: retargetBtn
            visible: menu.site
            label: I18n.tr("webdock.menu.retarget")
            enabled: !menu.forced && menu.loaded && menu.away
            Accessible.description: menu.forced ? I18n.tr("webdock.dock.forced") + " " + String(menu.pin.forced_by || "")
                : !menu.loaded ? I18n.tr("webdock.menu.not_loaded") : !menu.away ? I18n.tr("webdock.menu.at_home") : String(menu.pin.at)
            onClicked: menu.retargeted()
        }
        Button {
            id: unpinBtn
            visible: menu.site
            label: I18n.tr("webdock.menu.unpin")
            enabled: !menu.forced
            onClicked: menu.unpinned()
        }
        Button {
            id: closeBtn
            label: I18n.tr("webdock.dock.close")
            onClicked: menu.closed()
        }
    }
}
