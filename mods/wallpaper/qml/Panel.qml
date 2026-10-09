import QtQuick
import qs.core
import qs.components

// The wallpaper picker (Stage panel `mod:wallpaper:wallpaper`, docs/ux/wallpaper.md). A view: it
// subscribes to `mod.wallpaper`, pages the library with `wallpaper.thumbs` (thumbnails and palette chips
// are the daemon's, made for the rows asked for), and sends `wallpaper.*` actions. No polling: the
// picker's subscription is what keeps the document, and so the backend check, current.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: picker
    implicitWidth: 720
    implicitHeight: 480

    // ---- the document (the daemon's state; nothing is inferred here) -------------------------
    Watch { doc: "mod.wallpaper" }
    readonly property var doc: Store.docs["mod.wallpaper"] || ({})
    readonly property bool loaded: doc.loaded === true
    readonly property bool installed: doc.available === true
    readonly property var backend: doc.backend || ({})
    readonly property bool backendUp: backend.available === true
    readonly property var outputs: doc.outputs || ({})
    readonly property var outputNames: Object.keys(outputs).sort()
    readonly property var folders: (doc.library && doc.library.folders) || []
    readonly property int libraryCount: (doc.library && doc.library.count) || 0
    readonly property var rotationState: doc.rotation || ({})

    // ---- the picker's own view state ---------------------------------------------------------
    property string target: ""          // "" = every output, else one output's name
    property string folder: ""          // "" = every configured folder
    property string query: ""
    property string sort: "name"        // name | newest | random
    property int seed: 1
    property bool onlyFavourites: false
    property string errorKey: ""        // the last refused request, translated when shown

    readonly property int pageSize: 48
    property var rowCache: ({})         // library index -> row, as wallpaper.thumbs returns it
    property var pending: ({})          // page offset -> true while its request is out
    property int total: 0
    property int rowsRev: 0             // bumped when rows arrive: delegates re-read their row
    property int requestToken: 0        // a filter change makes older answers stale

    readonly property var selectedRow: rowAt(grid.currentIndex)
    readonly property bool showGrid: loaded && installed && total > 0

    function tr2(key, values) {
        var s = I18n.tr(key)
        for (var k in values) s = s.split("{" + k + "}").join(String(values[k]))
        return s
    }
    function fileUrl(p) {
        return "file://" + String(p).split("/").map(encodeURIComponent).join("/")
    }
    function baseName(p) {
        var parts = String(p).split("/")
        return parts[parts.length - 1]
    }
    function rowAt(i) {
        picker.rowsRev   // read, so a delegate's binding follows the pages as they arrive
        return (i >= 0 && rowCache[i] !== undefined) ? rowCache[i] : null
    }
    function pageFor(i) { return Math.floor(i / pageSize) * pageSize }

    // ---- paging ------------------------------------------------------------------------------
    function resetRows() {
        rowCache = ({})
        pending = ({})
        total = 0
        requestToken++
        rowsRev++
        grid.currentIndex = 0
        if (installed && loaded) requestPage(0)
    }
    function requestPage(offset) {
        if (pending[offset] === true) return
        var token = requestToken
        pending[offset] = true
        Store.act("wallpaper.thumbs", {
            offset: offset, limit: pageSize, query: query, sort: sort, seed: seed,
            favourites: onlyFavourites, folder: folder
        }, function (done, err) {
            if (token !== requestToken) return
            delete pending[offset]
            if (err) { errorKey = err.msg; return }
            var rows = (done && done.data && done.data.rows) || []
            for (var i = 0; i < rows.length; i++) rowCache[offset + i] = rows[i]
            total = (done && done.data && done.data.total) || 0
            rowsRev++
        })
    }

    Component.onCompleted: resetRows()
    onQueryChanged: resetRows()
    onSortChanged: resetRows()
    onSeedChanged: if (sort === "random") resetRows()
    onFolderChanged: resetRows()
    onOnlyFavouritesChanged: resetRows()
    onLoadedChanged: if (loaded) resetRows()
    onInstalledChanged: if (installed) resetRows()
    onLibraryCountChanged: resetRows()
    onTotalChanged: if (grid.currentIndex >= total) grid.currentIndex = Math.max(0, total - 1)

    // ---- actions -----------------------------------------------------------------------------
    function apply(path, allOutputs) {
        var args = { path: path }
        if (!allOutputs && target !== "") args.output = target
        Store.act("wallpaper.set", args, function (done, err) { errorKey = err ? err.msg : "" })
    }
    function favourite(path) {
        Store.act("wallpaper.favourite", { path: path }, function (done, err) { errorKey = err ? err.msg : "" })
    }
    function shuffle() {
        seed = Math.floor(Math.random() * 1000000) + 1
        sort = "random"
    }

    // ---- header: backend and rotation, in one line -----------------------------------------------
    Text {
        id: title
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.pad
        text: I18n.tr("mod-wallpaper.title")
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
    }
    Text {
        id: status
        anchors.verticalCenter: title.verticalCenter
        anchors.left: title.right
        anchors.right: parent.right
        anchors.leftMargin: Theme.pad
        anchors.rightMargin: Theme.pad
        elide: Text.ElideRight
        color: picker.backendUp ? Theme.dim : Theme.error
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: {
            if (!picker.loaded) return I18n.tr("mod-wallpaper.loading")
            if (!picker.installed) return I18n.tr(picker.backend.reason || "mod-wallpaper.backend.missing")
            var parts = []
            if (picker.backendUp) parts.push(picker.backend.id + (picker.backend.version ? " " + picker.backend.version : ""))
            else parts.push(I18n.tr(picker.backend.reason || "mod-wallpaper.backend.down"))
            if (picker.rotationState.on === true) parts.push(picker.tr2("mod-wallpaper.rotating", { min: picker.rotationState.interval_min }))
            else if (picker.rotationState.paused === true) parts.push(I18n.tr("mod-wallpaper.rotation.paused"))
            else parts.push(I18n.tr("mod-wallpaper.rotation.off"))
            return parts.join(" · ")
        }
    }

    // ---- target chips: every output; the span option greyed with its reason ---------------
    Flow {
        id: targets
        anchors.top: title.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pad
        anchors.topMargin: Theme.gap
        spacing: Theme.xs
        Button {
            label: I18n.tr("mod-wallpaper.target.all")
            primary: picker.target === ""
            onClicked: picker.target = ""
        }
        Repeater {
            model: picker.outputNames
            // An output's chip shows the image it has now (its current thumbnail), and its name.
            delegate: Rectangle {
                id: outChip
                required property string modelData
                readonly property var out: picker.outputs[modelData] || ({})
                readonly property bool chosen: picker.target === modelData
                width: chipRow.width + Theme.gap * 2
                height: Theme.controlH
                radius: Theme.rSm
                color: chosen ? Theme.accent : Theme.containerHigh
                activeFocusOnTab: true
                Keys.onReturnPressed: picker.target = modelData
                Keys.onEnterPressed: picker.target = modelData
                FocusRing {
                    anchors.fill: parent
                    corner: outChip.radius
                    shown: outChip.activeFocus
                }
                Row {
                    id: chipRow
                    x: Theme.gap
                    y: (outChip.height - height) / 2
                    spacing: Theme.xs
                    Image {
                        width: 32
                        height: 18
                        source: outChip.out.path ? picker.fileUrl(outChip.out.path) : ""
                        sourceSize.width: 32
                        sourceSize.height: 18
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== ""
                    }
                    Text {
                        height: 18
                        verticalAlignment: Text.AlignVCenter
                        color: outChip.chosen ? Theme.fgOnAccent : Theme.fg
                        font.pixelSize: Theme.fsLabel
                        font.family: Theme.fam(text, Theme.families)
                        text: outChip.modelData
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        picker.target = outChip.modelData
                        outChip.forceActiveFocus()
                    }
                }
            }
        }
        Chip {
            text: I18n.tr("mod-wallpaper.target.span")
            fg: Theme.outline
            edge: Theme.outline
        }
        Text {
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("mod-wallpaper.target.span.reason")
        }
    }

    // ---- toolbar: folders, search, sort, favourites, random ---------------------------------
    Flow {
        id: toolbar
        anchors.top: targets.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pad
        anchors.topMargin: Theme.xs
        spacing: Theme.xs
        Button {
            label: I18n.tr("mod-wallpaper.folder.all")
            primary: picker.folder === ""
            onClicked: picker.folder = ""
        }
        Repeater {
            model: picker.folders
            delegate: Button {
                required property var modelData
                label: picker.baseName(modelData.path)
                primary: picker.folder === modelData.path
                enabled: modelData.available === true
                onClicked: picker.folder = modelData.path
            }
        }
        Rectangle {
            id: searchBox
            width: 160
            height: Theme.controlH
            radius: Theme.rSm
            color: Theme.containerHigh
            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: Theme.gap
                anchors.rightMargin: Theme.gap
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                color: Theme.fg
                selectionColor: Theme.accent
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: picker.query
                onTextEdited: searchDebounce.restart()
                Keys.onEscapePressed: { text = ""; picker.query = ""; grid.forceActiveFocus() }
                Keys.onReturnPressed: grid.forceActiveFocus()
                Keys.onEnterPressed: grid.forceActiveFocus()
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: search.text.length === 0
                    text: I18n.tr("mod-wallpaper.search")
                    color: Theme.dim
                    font: search.font
                }
            }
        }
        Timer {
            id: searchDebounce
            interval: 250
            onTriggered: picker.query = search.text
        }
        Button {
            label: I18n.tr("mod-wallpaper.sort.name")
            primary: picker.sort === "name"
            onClicked: picker.sort = "name"
        }
        Button {
            label: I18n.tr("mod-wallpaper.sort.newest")
            primary: picker.sort === "newest"
            onClicked: picker.sort = "newest"
        }
        Button {
            label: I18n.tr("mod-wallpaper.favourites")
            primary: picker.onlyFavourites
            onClicked: picker.onlyFavourites = !picker.onlyFavourites
        }
        Button {
            label: I18n.tr("mod-wallpaper.random")
            enabled: picker.installed && picker.libraryCount > 0
            onClicked: picker.shuffle()
        }
    }

    // ---- footer: counts, the error in effect, cache, restart ------------------------------
    Row {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pad
        height: Theme.controlH
        spacing: Theme.gap
        Text {
            width: footer.width - cacheButton.width - restartButton.width - footer.spacing * 2
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: (picker.errorKey !== "" || picker.doc.error) ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: {
                var err = picker.errorKey !== "" ? I18n.tr(picker.errorKey)
                    : (picker.doc.error && picker.doc.error.key ? I18n.tr(picker.doc.error.key) : "")
                if (err !== "") return err
                return picker.tr2("mod-wallpaper.footer", {
                    backend: picker.backend.id || "",
                    version: picker.backend.version || "",
                    outputs: picker.outputNames.length,
                    images: picker.libraryCount
                })
            }
        }
        Button {
            id: cacheButton
            label: I18n.tr("mod-wallpaper.cache.clear")
            enabled: picker.installed
            onClicked: Store.act("wallpaper.cache.clear", {}, function () { picker.resetRows() })
        }
        Button {
            id: restartButton
            label: I18n.tr("mod-wallpaper.backend.restart")
            visible: picker.installed && picker.loaded && !picker.backendUp
            onClicked: Store.act("wallpaper.backend.restart", {}, function (done, err) {
                picker.errorKey = err ? err.msg : ""
            })
        }
    }

    // ---- preview: the selected image large, its palette, the one-step actions ----------------
    Item {
        id: preview
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pad
        anchors.bottomMargin: Theme.gap
        height: picker.showGrid && picker.selectedRow !== null ? 112 : 0
        visible: height > 0
        Image {
            id: previewImage
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 176
            height: 99
            source: picker.selectedRow && picker.selectedRow.thumb ? picker.fileUrl(picker.selectedRow.thumb) : ""
            sourceSize.width: 352
            sourceSize.height: 198
            asynchronous: true
            fillMode: Image.PreserveAspectFit
        }
        Column {
            id: details
            anchors.left: previewImage.right
            anchors.right: actions.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.pad
            anchors.rightMargin: Theme.pad
            spacing: Theme.xs
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: picker.selectedRow ? picker.selectedRow.name : ""
            }
            Row {
                spacing: 4
                Repeater {
                    model: picker.selectedRow && picker.selectedRow.palette ? picker.selectedRow.palette : []
                    delegate: Rectangle {
                        required property string modelData
                        width: 26
                        height: 26
                        radius: Theme.rSm
                        color: modelData
                        border.width: 1
                        border.color: Theme.outline
                    }
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                visible: picker.selectedRow !== null && picker.selectedRow.mono === true
                text: I18n.tr("mod-wallpaper.mono.warning")
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("mod-wallpaper.theme.unavailable")
            }
        }
        Column {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.xs
            Button {
                label: picker.target === "" ? I18n.tr("mod-wallpaper.apply.all") : I18n.tr("mod-wallpaper.apply")
                primary: true
                enabled: picker.backendUp && picker.selectedRow !== null
                onClicked: if (picker.selectedRow) picker.apply(picker.selectedRow.path, false)
            }
            Button {
                label: I18n.tr("mod-wallpaper.apply.everywhere")
                enabled: picker.backendUp && picker.selectedRow !== null
                onClicked: if (picker.selectedRow) picker.apply(picker.selectedRow.path, true)
            }
            Button {
                label: picker.selectedRow && picker.selectedRow.favourite === true
                    ? I18n.tr("mod-wallpaper.favourite.remove") : I18n.tr("mod-wallpaper.favourite.add")
                onClicked: if (picker.selectedRow) picker.favourite(picker.selectedRow.path)
            }
        }
    }

    // ---- body: the grid, or the state that replaces it ---------------------------------------
    Item {
        id: body
        anchors.top: toolbar.bottom
        anchors.bottom: preview.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pad
        anchors.topMargin: Theme.gap
        anchors.bottomMargin: Theme.gap
        clip: true

        // The empty and error states (docs/ux/wallpaper.md "States").
        Column {
            id: emptyState
            visible: !picker.showGrid
            anchors.centerIn: parent
            width: parent.width - Theme.pad * 4
            spacing: Theme.gap
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.family: Theme.fam(text, Theme.families)
                text: {
                    if (!picker.loaded) return I18n.tr("mod-wallpaper.loading")
                    if (!picker.installed) return I18n.tr("mod-wallpaper.empty.backend.title")
                    if (picker.folders.length === 0) return I18n.tr("mod-wallpaper.empty.folder.none.title")
                    if (picker.folders.every(function (f) { return f.available !== true }))
                        return I18n.tr("mod-wallpaper.empty.folder.missing.title")
                    if (picker.libraryCount === 0) return I18n.tr("mod-wallpaper.empty.library.title")
                    return I18n.tr("mod-wallpaper.empty.filter.title")
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.dim
                font.pixelSize: Theme.fsLabel
                font.family: Theme.fam(text, Theme.families)
                text: {
                    if (!picker.loaded) return ""
                    if (!picker.installed) return I18n.tr("mod-wallpaper.empty.backend.hint")
                    if (picker.folders.length === 0) return I18n.tr("mod-wallpaper.empty.folder.none.hint")
                    if (picker.folders.every(function (f) { return f.available !== true }))
                        return picker.tr2("mod-wallpaper.empty.folder.missing.hint", { path: picker.folders[0].path })
                    if (picker.libraryCount === 0) return I18n.tr("mod-wallpaper.empty.library.hint")
                    return I18n.tr("mod-wallpaper.empty.filter.hint")
                }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: picker.loaded && picker.installed && !picker.backendUp
                label: I18n.tr("mod-wallpaper.backend.restart")
                onClicked: Store.act("wallpaper.backend.restart", {}, function (done, err) {
                    picker.errorKey = err ? err.msg : ""
                })
            }
        }

        // Virtualised grid: delegates exist for the visible cells only, and a cell whose row has not
        // arrived asks for its page.
        GridView {
            id: grid
            anchors.fill: parent
            visible: picker.showGrid
            clip: true
            focus: true
            keyNavigationEnabled: true
            model: picker.total
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 150)))
            cellHeight: Math.round(cellWidth * 9 / 16) + 22

            Keys.onPressed: function (event) {
                var row = picker.selectedRow
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (row && row.path) picker.apply(row.path, (event.modifiers & Qt.ShiftModifier) !== 0)
                    event.accepted = true
                } else if (event.key === Qt.Key_F) {
                    if (row && row.path) picker.favourite(row.path)
                    event.accepted = true
                } else if (event.key === Qt.Key_R) {
                    picker.shuffle()
                    event.accepted = true
                } else if (event.key === Qt.Key_Backspace) {
                    picker.folder = ""
                    event.accepted = true
                } else if (event.key === Qt.Key_Slash) {
                    search.forceActiveFocus()
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

                function ensure() {
                    if (row === null) picker.requestPage(picker.pageFor(index))
                }
                Component.onCompleted: ensure()
                onIndexChanged: ensure()

                Rectangle {
                    id: tile
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: Theme.rSm
                    color: Theme.container
                    border.width: cell.current ? 2 : 0
                    border.color: Theme.accent
                    clip: true

                    Image {
                        id: thumb
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: parent.height - 18
                        source: cell.row && cell.row.thumb ? picker.fileUrl(cell.row.thumb) : ""
                        sourceSize.width: 256
                        sourceSize.height: 256
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== ""
                    }
                    // Palette chips: the daemon's, computed from the image's own colours.
                    Row {
                        anchors.left: parent.left
                        anchors.bottom: thumb.bottom
                        anchors.margins: 4
                        spacing: 2
                        visible: cell.row !== null && cell.row.palette !== undefined
                        Repeater {
                            model: cell.row && cell.row.palette ? cell.row.palette : []
                            delegate: Rectangle {
                                required property string modelData
                                width: 10
                                height: 10
                                radius: 2
                                color: modelData
                                border.width: 1
                                border.color: Theme.surface
                            }
                        }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 4
                        elide: Text.ElideRight
                        color: cell.row && cell.row.error ? Theme.error : Theme.fg
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: {
                            if (cell.row === null) return ""
                            if (cell.row.error) return I18n.tr(cell.row.error)
                            var marks = ""
                            if (cell.row.favourite === true) marks += "★ "
                            if (cell.row.on && cell.row.on.length > 0) marks += "● " + cell.row.on.join(" ") + "  "
                            return marks + cell.row.name
                        }
                    }
                    Text {
                        anchors.centerIn: thumb
                        visible: cell.row !== null && cell.row.error !== undefined
                        color: Theme.error
                        font.pixelSize: Theme.fsTitle
                        text: "!"
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: cell.row === null
                        color: Theme.dim
                        font.pixelSize: Theme.fsTitle
                        text: "…"
                    }
                    FocusRing {
                        anchors.fill: parent
                        corner: tile.radius
                        shown: grid.activeFocus && cell.current
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            grid.currentIndex = cell.index
                            grid.forceActiveFocus()
                        }
                        onDoubleClicked: if (cell.row && cell.row.path) picker.apply(cell.row.path, false)
                    }
                }
                Accessible.role: Accessible.ListItem
                Accessible.name: cell.row ? cell.row.name : ""
            }
        }
    }
}
