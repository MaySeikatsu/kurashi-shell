import QtQuick
import qs.core
import qs.components

// A pin's menu (docs/ux/webdock.md "Keyboard and a11y"): move the pin up or down in the strip, or remove it, opened by a
// right click or the menu key on its tile. A pin the configuration sets (`forced_by`) shows who sets it, and its edits
// are inert (provenance, rule 2): the buttons are disabled, never hidden.
Rectangle {
    id: menu
    property var pin: ({})
    property int index: 0
    property int count: 0
    readonly property bool forced: pin.forced_by !== undefined && pin.forced_by !== null
    signal moved(int to)
    signal removed()
    signal closed()

    radius: Theme.rLg
    color: Theme.container
    activeFocusOnTab: true
    Keys.onEscapePressed: menu.closed()
    // The menu takes the keyboard when it opens: the first button that is enabled has the focus.
    Component.onCompleted: Qt.callLater(function () {
        var first = [moveUp, moveDown, removeBtn, closeBtn].filter(function (b) { return b.enabled })
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
            id: closeBtn
            label: I18n.tr("webdock.dock.close")
            onClicked: menu.closed()
        }
    }
}
