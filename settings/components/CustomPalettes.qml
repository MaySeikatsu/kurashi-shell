import QtQuick
import "../core"

// The palettes' "Your own" category (I453, docs/ux/palettes.md "Custom palettes"): a card per palette of the user's with
// Edit, Duplicate and Delete (Delete asks once, on the tile), a greyed tile for a file that does not load (its reason and
// Delete), the New palette tile last, and the editor in their place while it is open. What there is comes from the
// daemon (`palette.list`: the folder, whether it can be written, each file's problem); Settings reads no files (rule 1).
Column {
    id: cu
    property var choices: []
    property var looks: ({})
    property var current
    property bool enabled: true
    signal picked(var value)

    // The daemon's `palette.list` reply; read when the view is built and after each save or delete.
    property var info: null
    // {mode: "new" | "edit", name}: the editor is open (on a copy of `name`, or on `name` itself).
    property var editing: null
    // The palette whose Delete asks now.
    property string asking: ""
    property string failure: ""

    readonly property bool writable: !cu.info || cu.info.writable !== false
    readonly property string dir: cu.info ? cu.info.dir : "~/.config/kurashi/palettes"
    function fileOf(name) {
        var list = (cu.info && cu.info.palettes) || []
        for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
        return null
    }
    function refresh() {
        Store.act("palette.list", {}, function (m) { if (m.t === "done") cu.info = m.data || null })
    }
    function remove(name) {
        cu.asking = ""
        cu.failure = ""
        Store.act("palette.delete", { name: name }, function (m) {
            if (m.t !== "done") cu.failure = Store.actError(m, "palettes.error.write")
            cu.refresh()
            Qt.callLater(function () { var n = cu.findChild(tiles, "palette-new"); if (n) n.forceActiveFocus() })
        })
    }
    function findChild(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) { var f = cu.findChild(kids[i], name); if (f) return f }
        return null
    }
    function open(mode, name) { cu.asking = ""; cu.failure = ""; cu.editing = { mode: mode, name: name } }
    // The editor went (saved or not): the list again, and the focus back on the tile it came from (or the New tile). Here,
    // not in the editor's handler: the editor is gone by the time the focus moves.
    function closeEditor() {
        const was = cu.editing
        cu.editing = null
        cu.refresh()
        Qt.callLater(function () {
            var t = was && was.mode === "edit" ? cu.findChild(tiles, "palette-edit:" + was.name) : null
            var n = t || cu.findChild(tiles, "palette-new")
            if (n) n.forceActiveFocus()
        })
    }
    // The palette a new one starts from: the one in effect, else the default.
    readonly property string startFrom: (typeof cu.current === "string" && cu.current !== "") ? cu.current : "wa-iro"
    Component.onCompleted: cu.refresh()
    // A file came, went or changed (the daemon's watch republished the offers): its problem and the folder again.
    onChoicesChanged: cu.refresh()

    width: parent ? parent.width : 600
    spacing: Theme.pad
    objectName: "custom-palettes"

    Loader {
        id: editorLoader
        width: cu.width
        active: cu.editing !== null
        visible: active
        sourceComponent: PaletteEditor {
            mode: cu.editing ? cu.editing.mode : "new"
            name: cu.editing ? cu.editing.name : ""
            listInfo: cu.info
            onClosed: saved => cu.closeEditor()
        }
    }

    Text {
        visible: !editorLoader.active && cu.choices.length === 0
        objectName: "palettes-empty"
        width: cu.width
        wrapMode: Text.Wrap
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: I18n.fmt("palettes.custom.empty", { dir: cu.dir })
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
    }
    Text {
        visible: !editorLoader.active && !cu.writable
        objectName: "palettes-read-only"
        width: cu.width
        wrapMode: Text.Wrap
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: I18n.fmt("palettes.custom.read_only", { dir: cu.dir })
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
    }

    Flow {
        id: tiles
        visible: !editorLoader.active
        width: cu.width
        spacing: Theme.pad
        Repeater {
            model: cu.choices
            delegate: Column {
                id: tile
                required property var modelData
                readonly property bool broken: modelData.enabled === false
                readonly property var file: cu.fileOf(modelData.value)
                readonly property bool fixed: !cu.writable || (tile.file && tile.file.managed)
                readonly property string name: I18n.tr(modelData.label)
                width: Math.max(156, actions.implicitWidth)
                spacing: Theme.gap
                objectName: "palette-tile:" + modelData.value
                // A palette that loads: its card, drawn as every palette's (a pick is a change).
                DecorCards {
                    visible: !tile.broken
                    width: 156
                    objectName: "palette-card:" + tile.modelData.value
                    choices: tile.broken ? [] : [tile.modelData]
                    looks: cu.looks
                    current: cu.current
                    enabled: cu.enabled
                    previewOnMove: false
                    cancellable: false
                    onPicked: v => cu.picked(v)
                }
                // A file that does not load: greyed, its file name and reason; only Delete.
                Rectangle {
                    visible: tile.broken
                    objectName: "palette-broken:" + tile.modelData.value
                    width: 156
                    height: 104 + Theme.gap + Theme.fs * 1.4
                    radius: Theme.rSm
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.outline
                    opacity: 0.75
                    Text {
                        anchors.fill: parent
                        anchors.margins: Theme.gap
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.fmt("palettes.custom.broken", {
                            file: tile.modelData.value + ".toml",
                            reason: I18n.tr(tile.modelData.reason || "palettes.error.parse")
                                + (tile.file && tile.file.problem && tile.file.problem.detail ? " (" + tile.file.problem.detail + ")" : "")
                        })
                    }
                }
                // Edit · Duplicate · Delete, or the question Delete asks.
                Row {
                    id: actions
                    spacing: 4
                    visible: cu.asking !== tile.modelData.value
                    Button {
                        objectName: "palette-edit:" + tile.modelData.value
                        visible: !tile.broken
                        label: I18n.tr("palettes.custom.edit")
                        accessibleName: I18n.tr("palettes.custom.edit") + " " + tile.name
                        onClicked: cu.open("edit", tile.modelData.value)
                    }
                    Button {
                        objectName: "palette-duplicate:" + tile.modelData.value
                        visible: !tile.broken
                        label: I18n.tr("palettes.custom.duplicate")
                        accessibleName: I18n.tr("palettes.custom.duplicate") + " " + tile.name
                        onClicked: cu.open("new", tile.modelData.value)
                    }
                    Button {
                        id: del
                        objectName: "palette-delete:" + tile.modelData.value
                        enabled: !tile.fixed
                        label: I18n.tr("palettes.custom.delete")
                        accessibleName: I18n.tr("palettes.custom.delete") + " " + tile.name
                        onClicked: {
                            cu.asking = tile.modelData.value
                            Qt.callLater(function () { confirm.forceActiveFocus() })
                        }
                    }
                }
                Column {
                    visible: cu.asking === tile.modelData.value
                    width: parent.width
                    spacing: 4
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        text: I18n.fmt("palettes.custom.delete_ask", { name: tile.name })
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Row {
                        spacing: 4
                        Button {
                            id: confirm
                            objectName: "palette-delete-confirm:" + tile.modelData.value
                            label: I18n.tr("palettes.custom.delete")
                            primary: true
                            onClicked: cu.remove(tile.modelData.value)
                            Keys.onEscapePressed: event => { cu.asking = ""; del.forceActiveFocus(); event.accepted = true }
                        }
                        Button {
                            objectName: "palette-delete-keep:" + tile.modelData.value
                            label: I18n.tr("palettes.custom.keep")
                            onClicked: { cu.asking = ""; del.forceActiveFocus() }
                            Keys.onEscapePressed: event => { cu.asking = ""; del.forceActiveFocus(); event.accepted = true }
                        }
                    }
                }
            }
        }
        // New palette: starts from the palette in effect.
        Rectangle {
            id: newTile
            objectName: "palette-new"
            width: 156
            height: 104
            radius: Theme.rSm
            color: newHover.hovered ? Theme.containerHigh : "transparent"
            border.width: 1
            border.color: Theme.outline
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("palettes.custom.new") + ", " + I18n.fmt("palettes.custom.new_hint", { name: Store.packLabel("palettes", cu.startFrom) })
            Keys.onReturnPressed: event => { cu.open("new", cu.startFrom); event.accepted = true }
            Keys.onEnterPressed: event => { cu.open("new", cu.startFrom); event.accepted = true }
            Keys.onSpacePressed: event => { cu.open("new", cu.startFrom); event.accepted = true }
            Column {
                anchors.centerIn: parent
                width: parent.width - 2 * Theme.gap
                spacing: 2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    text: Theme.iconFamily !== "" ? "add" : "+"
                    font.family: Theme.iconFamily !== "" ? Theme.iconFamily : Theme.fam(text, Theme.families)
                    font.pixelSize: 28
                    color: Theme.fg
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    text: I18n.tr("palettes.custom.new")
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.weight: Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    text: I18n.fmt("palettes.custom.new_hint", { name: Store.packLabel("palettes", cu.startFrom) })
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                }
            }
            HoverHandler { id: newHover }
            MouseArea {
                anchors.fill: parent
                enabled: cu.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: cu.open("new", cu.startFrom)
            }
            FocusRing { anchors.fill: parent; shown: newTile.activeFocus; corner: newTile.radius }
        }
    }
    Text {
        visible: cu.failure !== ""
        width: cu.width
        wrapMode: Text.Wrap
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        text: cu.failure
        color: Theme.error
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
    }
}
