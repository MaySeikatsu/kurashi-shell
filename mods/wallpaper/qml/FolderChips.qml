import QtQuick
import qs.core
import qs.components

// The library's folders (docs/ux/appearance-menu.md "Panes", Wallpaper): All (with more than one folder), each configured
// folder — a click, Return or Space browses it alone, × or Delete removes it, a missing one is struck with "not found" —
// and "+ Add folder", which opens a path field (`~/…` or absolute; Enter adds, Esc closes). The folders are the mod's
// setting (`mods.wallpaper.folders`), written at once.
ChipRow {
    id: fr
    readonly property bool many: host !== null && host.folderList.length > 1
    function browse(i) {
        if (!host.folderAvailable(i)) return
        var p = host.folderPath(i)
        // the chosen folder's chip again: back to every folder
        host.folder = host.folderRoot === p && host.folder === p ? "" : p
    }
    PickButton {
        objectName: "wall-folder-all"
        visible: fr.many
        label: I18n.tr("mod-wallpaper.folder.all")
        selected: fr.host.folder === ""
        onActivated: fr.host.folder = ""
    }
    Repeater {
        model: fr.host ? fr.host.folderList : []
        delegate: Rectangle {
            id: fchip
            required property string modelData
            required property int index
            // the chosen folder (or, with one folder and none chosen, the library itself)
            readonly property bool here: fr.host.folderRoot !== "" ? fr.host.folderRoot === fr.host.folderPath(index)
                : (!fr.many && fr.host.folder === "")
            readonly property bool ok: fr.host.folderAvailable(index)
            objectName: "wall-folder-" + index
            height: 28
            width: frow.implicitWidth + Theme.pad
            radius: height / 2
            color: here ? Qt.alpha(Theme.accent, 0.22) : Theme.containerHigh
            border.width: here ? 1 : 0
            border.color: Theme.accent
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData + (ok ? "" : ", " + I18n.tr("appearance-menu.wallpaper.folder.missing"))
            Accessible.checkable: true
            Accessible.checked: here
            Keys.onReturnPressed: fr.browse(index)
            Keys.onEnterPressed: fr.browse(index)
            Keys.onSpacePressed: fr.browse(index)
            Keys.onDeletePressed: fr.host.removeFolder(index)
            Row {
                id: frow
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.pad / 2 + 2
                spacing: 4
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: fchip.ok ? "folder" : "warning"
                    glyph: fchip.ok ? "▢" : "!"
                    size: Theme.fs
                    color: fchip.ok ? Theme.dim : Theme.error
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: fchip.ok ? Theme.fg : Theme.dim
                    font.pixelSize: Theme.fsLabel
                    font.strikeout: !fchip.ok
                    font.family: Theme.fam(text, Theme.families)
                    // a long path keeps its start and its folder's name
                    width: Math.min(implicitWidth, fr.width * 0.55)
                    elide: Text.ElideMiddle
                    text: fchip.modelData
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !fchip.ok
                    color: Theme.error
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("appearance-menu.wallpaper.folder.missing")
                }
                // remove
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 9
                    color: xHover.hovered ? Theme.selected : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("appearance-menu.wallpaper.folder.remove")
                    Icon { anchors.centerIn: parent; name: "close"; glyph: "×"; size: Theme.fs - 1; color: Theme.dim }
                    HoverHandler { id: xHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: fr.host.removeFolder(fchip.index) }
                }
            }
            TapHandler { onTapped: { fchip.forceActiveFocus(); fr.browse(fchip.index) } }
            FocusRing { anchors.fill: parent; corner: fchip.radius; shown: fchip.activeFocus }
        }
    }
    PickButton {
        id: addButton
        objectName: "wall-folder-add"
        visible: fr.host !== null && !fr.host.adding
        label: "+ " + I18n.tr("appearance-menu.wallpaper.folder.add")
        onActivated: { fr.host.adding = true; fr.host.later(function () { addField.forceActiveFocus() }) }
    }
    // the path field: `~/…` or an absolute path; Enter adds, Esc closes it
    Rectangle {
        visible: fr.host !== null && fr.host.adding
        width: Math.min(fr.width, 320)
        height: 28
        radius: Theme.rSm
        color: Theme.containerHigh
        border.width: 1
        border.color: addField.activeFocus ? Theme.focusRing : Theme.outline
        TextInput {
            id: addField
            objectName: "wall-folder-field"
            anchors.fill: parent
            anchors.leftMargin: Theme.gap
            anchors.rightMargin: Theme.gap
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
            Accessible.role: Accessible.EditableText
            Accessible.name: I18n.tr("appearance-menu.wallpaper.folder.field")
            function done(add) {
                if (add) fr.host.addFolder(text)
                else fr.host.adding = false
                text = ""
                fr.host.later(function () { addButton.forceActiveFocus() })
            }
            Keys.onReturnPressed: done(true)
            Keys.onEnterPressed: done(true)
            Keys.onEscapePressed: done(false)
            // Left and Right edit the path, not the row
            Keys.onLeftPressed: event => event.accepted = false
            Keys.onRightPressed: event => event.accepted = false
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: addField.text === ""
                color: Theme.dim
                font: addField.font
                text: I18n.tr("appearance-menu.wallpaper.folder.field")
            }
        }
    }
}
