import QtQuick
import qs.core
import qs.components

// The wallpaper mod's compact picker for the appearance menu's Wallpaper pane (W84, docs/ux/appearance-menu.md "Panes"):
// the sources (Local, and Wallhaven while it is on), Local's folders — shown, added, removed, one picked to browse —,
// search, the grid, and one row for rotation (Shuffle now, Rotate every, Order). The menu loads it beside this mod's
// Panel.qml (the `mods` document's file for `panel:wallpaper`), so it exists only while the mod is on and the pane is
// shown; the mod's own picker (Panel.qml) is unchanged. The same documents and actions as Panel.qml: `mod.wallpaper`,
// `wallpaper.thumbs` pages, `wallpaper.preview` (the selected picture's colours for the menu's preview), `wallpaper.set`,
// `wallpaper.random`; the folders and rotation are this mod's settings, applied at once (they are not appearance: the
// menu's preview session is for the look). Keys: arrows move in the grid, Enter sets the picture (on every output, with
// the theme's picture), / searches, Backspace leaves a folder.
Item {
    id: picker
    required property var store
    required property var theme
    required property var i18n
    property var menu: null           // the appearance menu (its host decides nothing here)
    property string output: ""        // the output the menu was asked on

    implicitHeight: col.implicitHeight

    Watch { doc: "mod.wallpaper" }
    Watch { doc: "config" }
    readonly property var doc: Store.docs["mod.wallpaper"] || ({})
    readonly property bool loaded: doc.loaded === true
    readonly property bool installed: doc.available === true
    readonly property var backend: doc.backend || ({})
    readonly property bool backendUp: backend.available === true
    readonly property var libFolders: (doc.library && doc.library.folders) || []
    readonly property int libraryCount: (doc.library && doc.library.count) || 0
    readonly property var configValues: (Store.docs["config"] && Store.docs["config"].values) || ({})
    function cfg(key, d) { var p = configValues[key]; return p && p.value !== undefined ? p.value : d }
    readonly property var folders: { var v = cfg("mods.wallpaper.folders", []); return Array.isArray(v) ? v : [] }
    readonly property bool wallhavenOn: cfg("mods.wallpaper.wallhaven", true) === true
    readonly property int rotate: Number(cfg("mods.wallpaper.rotate", 0))
    readonly property string rotateOrder: String(cfg("mods.wallpaper.rotate_order", "alphabetical"))
    readonly property bool followsPicture: String(cfg("theme.colors.palette", "")) === "wallpaper"
    readonly property string extraction: String(cfg("theme.colors.extraction", ""))
    readonly property string schemeNow: {
        var t = Store.docs["theme"]
        return t && t.appearance && t.appearance.scheme_effective === "light" ? "light" : "dark"
    }

    // ---- view state ----
    property string source: "local"       // local | wallhaven
    onWallhavenOnChanged: if (!wallhavenOn) source = "local"
    property string folder: ""            // "" = every folder, else one configured folder (its path as the doc names it)
    property string query: ""
    property bool adding: false           // the "Add folder" field is open
    property string errorKey: ""
    readonly property int pageSize: 48
    property var rowCache: ({})
    property var pending: ({})
    property int total: 0
    property int rowsRev: 0
    property int requestToken: 0
    property bool resetQueued: false
    property var gate: ({ open: true })
    readonly property var selectedRow: rowAt(grid.currentIndex)
    readonly property bool showGrid: loaded && installed && total > 0
    // What the menu's live preview shows: the selected picture, and its colours while the theme follows the picture.
    readonly property string previewPath: source === "local" && selectedRow && selectedRow.path ? selectedRow.path : ""
    property var previewRoles: null
    property int previewToken: 0
    // The Wallhaven tab's host contract (Wallhaven.qml): the theme goes with the picture.
    readonly property bool withTheme: true

    function tr2(key, values) {
        var s = I18n.tr(key)
        for (var k in values) s = s.split("{" + k + "}").join(String(values[k]))
        return s
    }
    function fileUrl(p) { return "file://" + String(p).split("/").map(encodeURIComponent).join("/") }
    function baseName(p) { var parts = String(p).split("/"); return parts[parts.length - 1] || String(p) }
    function later(fn) { var g = gate; Qt.callLater(function () { if (g.open) fn() }) }
    function rowAt(i) {
        picker.rowsRev
        return (i >= 0 && rowCache[i] !== undefined) ? rowCache[i] : null
    }
    function pageFor(i) { return Math.floor(i / pageSize) * pageSize }
    function scheduleReset() {
        if (resetQueued) return
        resetQueued = true
        later(function () { picker.resetQueued = false; picker.resetRows() })
    }
    function resetRows() {
        rowCache = ({})
        pending = ({})
        requestToken++
        rowsRev++
        grid.currentIndex = 0
        if (installed && loaded) requestPage(0)
    }
    function requestPage(offset) {
        if (pending[offset] === true) return
        var g = gate, token = requestToken
        pending[offset] = true
        Store.act("wallpaper.thumbs", { offset: offset, limit: pageSize, query: query, sort: "name", seed: 1,
                                        favourites: false, folder: folder }, function (done, err) {
            if (!g.open || token !== picker.requestToken) return
            delete pending[offset]
            if (err) { errorKey = err.msg; return }
            var data = (done && done.data) || {}
            var rows = data.rows || []
            for (var i = 0; i < rows.length; i++) rowCache[offset + i] = rows[i]
            total = data.total || 0
            rowsRev++
        })
    }
    Component.onCompleted: scheduleReset()
    Component.onDestruction: gate.open = false
    onQueryChanged: scheduleReset()
    onFolderChanged: scheduleReset()
    onLoadedChanged: if (loaded) scheduleReset()
    onInstalledChanged: if (installed) scheduleReset()
    onLibraryCountChanged: scheduleReset()

    // ---- the selected picture's colours (a dry run), debounced while the selection moves ----
    Timer { id: previewDebounce; interval: 160; onTriggered: picker.runPreview() }
    onPreviewPathChanged: previewDebounce.restart()
    onFollowsPictureChanged: previewDebounce.restart()
    function runPreview() {
        var token = ++previewToken
        if (previewPath === "" || !followsPicture) { previewRoles = null; return }
        var g = gate
        Store.act("wallpaper.preview", { path: previewPath, scheme: schemeNow, extraction: extraction }, function (done, err) {
            if (!g.open || token !== picker.previewToken) return
            picker.previewRoles = !err && done && done.data && done.data.roles ? done.data.roles : null
        })
    }

    // ---- actions ----
    // (the Wallhaven tab calls this too: host.setWallpaper(path, allOutputs, withTheme, origin))
    function setWallpaper(path, allOutputs, withThemeNow, origin) {
        var args = { path: path, theme: withThemeNow !== false }
        if (origin) args.origin = origin
        var g = gate
        Store.act("wallpaper.set", args, function (done, err) { if (g.open) picker.errorKey = err ? err.msg : "" })
    }
    function originOf(item) { return null }
    function applySelected() {
        var r = selectedRow
        if (backendUp && r && r.path && r.error === undefined) setWallpaper(r.path, true, true, null)
    }
    function setFolders(list) {
        var g = gate
        Store.apply([{ set: "mods.wallpaper.folders", value: list }], function (errs) {
            if (g.open) picker.errorKey = errs && errs.length > 0 ? (errs[0].code || "") : ""
        })
    }
    function addFolder(path) {
        var p = String(path).trim()
        if (p === "") { adding = false; return }
        if (folders.indexOf(p) < 0) setFolders(folders.concat([p]))
        adding = false
        later(function () { addButton.forceActiveFocus() })
    }
    function removeFolder(i) {
        var list = folders.slice()
        var gone = libPath(i)
        list.splice(i, 1)
        if (folder !== "" && folder === gone) folder = ""
        setFolders(list)
    }
    // A configured folder's path as the document names it (expanded), by place; the configured text otherwise.
    function libPath(i) { return i < libFolders.length && libFolders[i].path ? libFolders[i].path : folders[i] }
    function available(i) { return i < libFolders.length ? libFolders[i].available === true : true }
    function setRotate(min) { Store.apply([{ set: "mods.wallpaper.rotate", value: min }], null) }
    function setOrder(o) { Store.apply([{ set: "mods.wallpaper.rotate_order", value: o }], null) }

    Column {
        id: col
        width: picker.width
        spacing: Theme.gap

        // the sources: Local, Wallhaven (while it is on)
        Row {
            spacing: Theme.xs
            Accessible.role: Accessible.PageTabList
            PickButton {
                objectName: "wall-source-local"
                label: I18n.tr("appearance-menu.wallpaper.local")
                selected: picker.source === "local"
                Accessible.role: Accessible.PageTab
                onActivated: picker.source = "local"
            }
            PickButton {
                objectName: "wall-source-wallhaven"
                visible: picker.wallhavenOn
                label: I18n.tr("mod-wallpaper.tab.wallhaven")
                selected: picker.source === "wallhaven"
                Accessible.role: Accessible.PageTab
                onActivated: picker.source = "wallhaven"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: Theme.gap
                color: picker.backendUp || !picker.loaded ? Theme.dim : Theme.error
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: !picker.loaded ? I18n.tr("mod-wallpaper.loading")
                    : (!picker.installed ? I18n.tr(picker.backend.reason || "mod-wallpaper.backend.missing")
                    : (picker.backendUp ? picker.tr2("appearance-menu.wallpaper.count", { n: picker.libraryCount })
                    : I18n.tr(picker.backend.reason || "mod-wallpaper.backend.down")))
            }
        }

        // ---- Local ----
        // the folders: All, then each configured folder (a missing one struck and dimmed), × removes; + adds one
        Flow {
            id: folderRow
            visible: picker.source === "local"
            width: parent.width
            spacing: Theme.xs
            PickButton {
                label: I18n.tr("mod-wallpaper.folder.all")
                selected: picker.folder === ""
                visible: picker.folders.length > 1
                onActivated: picker.folder = ""
            }
            Repeater {
                model: picker.folders
                delegate: Rectangle {
                    id: fchip
                    required property string modelData
                    required property int index
                    readonly property bool here: picker.folder !== "" && picker.folder === picker.libPath(index)
                    readonly property bool ok: picker.available(index)
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
                    Keys.onReturnPressed: if (ok) picker.folder = here ? "" : picker.libPath(index)
                    Keys.onSpacePressed: if (ok) picker.folder = here ? "" : picker.libPath(index)
                    Keys.onDeletePressed: picker.removeFolder(index)
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
                            width: Math.min(implicitWidth, folderRow.width * 0.55)
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
                            TapHandler { onTapped: picker.removeFolder(fchip.index) }
                        }
                    }
                    TapHandler { onTapped: if (fchip.ok) picker.folder = fchip.here ? "" : picker.libPath(fchip.index) }
                    FocusRing { anchors.fill: parent; corner: fchip.radius; shown: fchip.activeFocus }
                }
            }
            PickButton {
                id: addButton
                objectName: "wall-folder-add"
                visible: !picker.adding
                label: "+ " + I18n.tr("appearance-menu.wallpaper.folder.add")
                onActivated: { picker.adding = true; picker.later(function () { addField.forceActiveFocus() }) }
            }
            // the path field: `~/…` or an absolute path; Enter adds, Esc closes it
            Rectangle {
                visible: picker.adding
                width: Math.min(folderRow.width, 320)
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
                    Keys.onReturnPressed: { picker.addFolder(text); text = "" }
                    Keys.onEnterPressed: { picker.addFolder(text); text = "" }
                    Keys.onEscapePressed: { text = ""; picker.adding = false; picker.later(function () { addButton.forceActiveFocus() }) }
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

        // search
        Rectangle {
            visible: picker.source === "local" && picker.loaded && picker.installed && picker.libraryCount > 0
            width: parent.width
            height: Theme.controlH
            radius: Theme.rSm
            color: Theme.containerHigh
            border.width: search.activeFocus ? 1 : 0
            border.color: Theme.focusRing
            TextInput {
                id: search
                objectName: "wall-search"
                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                activeFocusOnTab: true
                onTextEdited: searchDebounce.restart()
                Keys.onEscapePressed: event => { if (text !== "") { text = ""; picker.query = ""; event.accepted = true } else event.accepted = false }
                Keys.onReturnPressed: grid.forceActiveFocus()
                Keys.onEnterPressed: grid.forceActiveFocus()
                Keys.onDownPressed: grid.forceActiveFocus()
                Accessible.role: Accessible.EditableText
                Accessible.name: I18n.tr("mod-wallpaper.search")
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0
                    text: I18n.tr("mod-wallpaper.search")
                    color: Theme.dim
                    font: search.font
                }
            }
            Timer { id: searchDebounce; interval: 250; onTriggered: picker.query = search.text }
        }

        // the grid, or the state in its place
        Item {
            visible: picker.source === "local"
            width: parent.width
            height: picker.showGrid ? Math.min(3, Math.ceil(picker.total / grid.columns)) * grid.cellHeight : emptyCol.implicitHeight + 2 * Theme.pad
            Column {
                id: emptyCol
                visible: !picker.showGrid
                anchors.centerIn: parent
                width: parent.width - 2 * Theme.pad
                spacing: 4
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.weight: Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                    text: {
                        if (!picker.loaded) return I18n.tr("mod-wallpaper.loading")
                        if (!picker.installed) return I18n.tr("mod-wallpaper.empty.backend.title")
                        if (picker.folders.length === 0) return I18n.tr("appearance-menu.wallpaper.none")
                        if (picker.libFolders.length > 0 && picker.libFolders.every(function (f) { return f.available !== true }))
                            return I18n.tr("mod-wallpaper.empty.folder.missing.title")
                        if (picker.libraryCount === 0) return I18n.tr("mod-wallpaper.empty.library.title")
                        return I18n.tr("mod-wallpaper.empty.filter.title")
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: {
                        if (!picker.loaded) return ""
                        if (!picker.installed) return I18n.tr("mod-wallpaper.empty.backend.hint")
                        if (picker.folders.length === 0) return I18n.tr("appearance-menu.wallpaper.none.hint")
                        if (picker.libFolders.length > 0 && picker.libFolders.every(function (f) { return f.available !== true }))
                            return I18n.tr("appearance-menu.wallpaper.missing.hint")
                        if (picker.libraryCount === 0) return picker.tr2("appearance-menu.wallpaper.empty.hint", { path: picker.folders.join(", ") })
                        return I18n.tr("mod-wallpaper.empty.filter.hint")
                    }
                }
            }
            GridView {
                id: grid
                objectName: "wall-grid"
                KineticWheel { view: grid }
                anchors.fill: parent
                visible: picker.showGrid
                clip: true
                activeFocusOnTab: true
                keyNavigationEnabled: true
                highlightMoveDuration: Theme.quickMs
                readonly property int columns: 4
                model: picker.total
                cellWidth: Math.floor(width / columns)
                cellHeight: Math.round((cellWidth - 6) * 9 / 16) + 6
                boundsBehavior: Flickable.StopAtBounds
                Accessible.role: Accessible.List
                Accessible.name: I18n.tr("appearance-menu.wallpaper.grid")
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        picker.applySelected()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Slash) {
                        search.forceActiveFocus()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Backspace && picker.folder !== "") {
                        picker.folder = ""
                        event.accepted = true
                    }
                }
                delegate: Item {
                    id: cell
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    readonly property var row: picker.rowAt(index)
                    readonly property bool current: GridView.isCurrentItem
                    readonly property bool onScreen: !!row && !!row.on && row.on.length > 0
                    Component.onCompleted: if (row === null) picker.requestPage(picker.pageFor(index))
                    onIndexChanged: if (row === null) picker.requestPage(picker.pageFor(index))
                    Accessible.role: Accessible.ListItem
                    Accessible.name: row ? row.name + (onScreen ? ", " + I18n.tr("mod-wallpaper.on") + " " + row.on.join(", ") : "") : ""
                    Accessible.selected: current
                    Rectangle {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: Theme.rSm
                        color: Theme.container
                        clip: true
                        border.width: cell.current ? 2 : 0
                        border.color: Theme.accent
                        Image {
                            id: thumb
                            Component.onCompleted: Light.addPicture(thumb, Window.window)
                            Component.onDestruction: Light.removePicture(thumb)
                            anchors.fill: parent
                            anchors.margins: tile.border.width
                            source: cell.row && cell.row.thumb ? picker.fileUrl(cell.row.thumb) : ""
                            sourceSize.width: 256
                            sourceSize.height: 256
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !thumb.visible
                            color: cell.row && cell.row.error ? Theme.error : Theme.dim
                            font.pixelSize: Theme.fsTitle
                            text: cell.row && cell.row.error ? "!" : "…"
                        }
                        // the picture on a screen now
                        Rectangle {
                            visible: cell.onScreen
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
                            width: 10; height: 10; radius: 5
                            color: Theme.accent
                            border.width: 2
                            border.color: Theme.surface
                        }
                        FocusRing { anchors.fill: parent; corner: tile.radius; shown: grid.activeFocus && cell.current }
                        TapHandler {
                            onTapped: { grid.currentIndex = cell.index; grid.forceActiveFocus() }
                            onDoubleTapped: { grid.currentIndex = cell.index; picker.applySelected() }
                        }
                    }
                }
            }
            ScrollEdge { view: grid }
        }

        // rotation: Shuffle now · Rotate every … · Order
        Flow {
            visible: picker.source === "local"
            width: parent.width
            spacing: Theme.xs
            PickButton {
                objectName: "wall-shuffle"
                label: I18n.tr("appearance-menu.wallpaper.shuffle")
                enabled: picker.backendUp && picker.libraryCount > 0
                onActivated: Store.act("wallpaper.random", {}, function (done, err) { picker.errorKey = err ? err.msg : "" })
            }
            Text {
                height: 28
                verticalAlignment: Text.AlignVCenter
                leftPadding: Theme.gap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("appearance-menu.wallpaper.rotate")
            }
            Repeater {
                // the usual intervals, and the configured one when it is another
                model: {
                    var l = [0, 15, 30, 60]
                    if (l.indexOf(picker.rotate) < 0) l.push(picker.rotate)
                    return l
                }
                delegate: PickButton {
                    required property int modelData
                    label: modelData === 0 ? I18n.tr("appearance-menu.wallpaper.rotate.off")
                        : picker.tr2("appearance-menu.wallpaper.rotate.min", { n: modelData })
                    selected: picker.rotate === modelData
                    onActivated: picker.setRotate(modelData)
                }
            }
            PickButton {
                visible: picker.rotate > 0
                label: I18n.tr(picker.rotateOrder === "shuffle" ? "appearance-menu.wallpaper.order.shuffle" : "appearance-menu.wallpaper.order.name")
                selected: picker.rotateOrder === "shuffle"
                Accessible.description: I18n.tr("appearance-menu.wallpaper.order")
                onActivated: picker.setOrder(picker.rotateOrder === "shuffle" ? "alphabetical" : "shuffle")
            }
        }

        // ---- Wallhaven: the mod's own tab, made only while chosen ----
        Loader {
            active: picker.source === "wallhaven"
            visible: active
            width: parent.width
            height: active ? 380 : 0
            sourceComponent: Component { Wallhaven { host: picker } }
        }

        Text {
            visible: picker.errorKey !== "" || !!(picker.doc.error && picker.doc.error.key)
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.error
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: picker.errorKey !== "" ? I18n.tr(picker.errorKey) : (picker.doc.error && picker.doc.error.key ? I18n.tr(picker.doc.error.key) : "")
        }
    }
}
