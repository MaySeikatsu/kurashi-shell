import QtQuick
import qs.core
import qs.components

// The wallpaper picker (Stage panel `mod:wallpaper:wallpaper`, docs/ux/wallpaper.md). A view: it subscribes to
// `mod.wallpaper` and `config`, pages the library with `wallpaper.thumbs` (thumbnails, palette chips, pairs and
// subfolders are the daemon's), asks `wallpaper.preview` for the theme a picture would give (a dry run of the
// `wallpaper` theme source), and sends `wallpaper.*` actions and config intents. It fills the Stage card: no
// frame of its own, the card is the frame. Keys: arrows move, Enter applies (with theme when the theme switch is
// on), Ctrl+Enter wallpaper only, Shift+Enter to every output, F keeps the look, R shuffles, T the theme switch,
// Backspace goes up a folder, / searches.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: picker
    // The Stage card's content width (360 minus 2 x 16 px); a host that gives a width wins.
    implicitWidth: 328
    implicitHeight: 640

    // ---- documents (the daemon's state; nothing is inferred here) ----------------------------
    Watch { doc: "mod.wallpaper" }
    Watch { doc: "config" }
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
    readonly property var looks: doc.favourites || []
    readonly property string themeImage: (doc.theme && doc.theme.image) || ""
    readonly property var themeDoc: Store.docs["theme"] || ({})
    readonly property var configValues: (Store.docs["config"] && Store.docs["config"].values) || ({})
    readonly property string configScheme: configValues["theme.colors.scheme"]
        && configValues["theme.colors.scheme"].value === "light" ? "light" : "dark"
    readonly property string configPalette: configValues["theme.colors.palette"]
        ? String(configValues["theme.colors.palette"].value || "") : ""
    readonly property bool themeFollowsWallpaper: configPalette === "wallpaper"

    // ---- the picker's own view state ----------------------------------------------------------
    property string target: ""          // "" = every output, else one output's name
    property string folder: ""          // "" = every folder, else a folder under a configured one (the breadcrumb)
    property string query: ""
    property string sort: "name"        // name | newest | random
    property int seed: 1
    property bool onlyLooks: false
    property bool withTheme: true       // the theme switch: Apply also makes the theme follow the picture
    property string schemeChoice: ""    // the scheme the preview shows; "" follows the configured scheme
    readonly property string previewScheme: schemeChoice !== "" ? schemeChoice : configScheme
    property string errorKey: ""        // the last refused request, translated when shown
    property var subfolders: []         // folders under `folder`, from the last page (name, path, count)

    readonly property int pageSize: 48
    readonly property int columns: Math.max(2, Math.floor(grid.width / 160))
    property var rowCache: ({})         // library index -> row, as wallpaper.thumbs returns it
    property var pending: ({})          // page offset -> true while its request is out
    property int total: 0
    property int rowsRev: 0             // bumped when rows arrive: delegates re-read their row
    property int requestToken: 0        // a filter change makes older answers stale
    property bool resetQueued: false    // one reset per turn, however many filters change at once

    // Closed when the panel is destroyed: the callbacks below capture this object, never the panel itself.
    property var gate: ({ open: true })
    readonly property var selectedRow: rowAt(grid.currentIndex)
    readonly property bool showGrid: loaded && installed && total > 0

    // The theme preview of the selected picture (wallpaper.preview), and whether it is the current one.
    property var themePreview: null     // the reply of wallpaper.preview: palette roles of the selected picture
    property string previewError: ""
    property bool previewBusy: false
    property int previewToken: 0
    readonly property bool previewCurrent: themePreview !== null && selectedRow !== null
        && themePreview.path === selectedRow.path && themePreview.scheme === previewScheme

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
    // The configured folder a path lies in (the breadcrumb's first crumb), "" when none does.
    function rootOf(p) {
        for (var i = 0; i < folders.length; i++) {
            var f = folders[i].path
            if (p === f || p.indexOf(f + "/") === 0) return f
        }
        return ""
    }
    // The chips of the folder row: All, then the configured folders (none chosen), or the breadcrumb of the chosen
    // folder and the folders under it. Each chip: {kind, label, path, here}; `here` marks the current folder.
    function chipModel() {
        var out = [{ kind: "all", label: I18n.tr("mod-wallpaper.folder.all"), path: "", here: folder === "" }]
        if (folder === "") {
            for (var i = 0; i < folders.length; i++) {
                if (folders[i].available !== true) continue
                out.push({ kind: "root", label: baseName(folders[i].path), path: folders[i].path, here: false })
            }
            return out
        }
        var root = rootOf(folder)
        if (root === "") return out
        out.push({ kind: "crumb", label: baseName(root), path: root, here: folder === root })
        var rest = folder.substring(root.length + 1).split("/")
        var acc = root
        for (var j = 0; j < rest.length; j++) {
            acc = acc + "/" + rest[j]
            out.push({ kind: "crumb", label: rest[j], path: acc, here: acc === folder })
        }
        for (var k = 0; k < subfolders.length; k++) {
            out.push({ kind: "sub", label: subfolders[k].name + "  " + subfolders[k].count,
                path: subfolders[k].path, here: false })
        }
        return out
    }
    // The chips of the folder row end with the looks filter (a toggle, not a folder).
    function chipsWithLooks() {
        var out = chipModel()
        out.push({ kind: "looks", label: I18n.tr("mod-wallpaper.favourites"), path: "", here: onlyLooks })
        return out
    }
    function activateChip(c) {
        if (c.kind === "looks") onlyLooks = !onlyLooks
        else folder = c.path
    }
    // Changing the folder rebuilds the chip row, which destroys the chip that asked: the focus moves on a later turn.
    function activateChipAndFocus(c) {
        activateChip(c)
        later(focusGrid)
    }
    // Up from the first grid row: the folder row takes the focus, on the current folder's chip.
    function focusFolderRow() {
        var model = chipModel()
        for (var i = 0; i < model.length; i++) {
            if (model[i].here) { chips.itemAt(i).forceActiveFocus(); return }
        }
        chips.itemAt(0).forceActiveFocus()
    }
    function upFolder() {
        if (folder === "") return
        var up = folder.substring(0, folder.lastIndexOf("/"))
        folder = rootOf(up) === "" ? "" : up
    }

    // ---- paging: one reset per turn, one request per page -------------------------------------
    function scheduleReset() {
        if (resetQueued) return
        resetQueued = true
        later(function () { picker.resetQueued = false; picker.resetRows() })
    }
    // The count stays until the new page answers: clearing it hid the grid for a turn (a flicker, and focus lost from
    // the search field while typing).
    function resetRows() {
        rowCache = ({})
        pending = ({})
        requestToken++
        rowsRev++
        subfolders = []
        grid.currentIndex = 0
        if (installed && loaded) requestPage(0)
    }
    function requestPage(offset) {
        if (pending[offset] === true) return
        var g = gate
        var token = requestToken
        pending[offset] = true
        Store.act("wallpaper.thumbs", {
            offset: offset, limit: pageSize, query: query, sort: sort, seed: seed,
            favourites: onlyLooks, folder: folder
        }, function (done, err) {
            if (!g.open || token !== picker.requestToken) return
            delete pending[offset]
            if (err) { errorKey = err.msg; return }
            var data = (done && done.data) || {}
            var rows = data.rows || []
            for (var i = 0; i < rows.length; i++) rowCache[offset + i] = rows[i]
            total = data.total || 0
            if (offset === 0) subfolders = data.children || []
            rowsRev++
        })
    }

    // The Stage card takes the keyboard when the panel opens, and queues that before the panel exists; the picker
    // asks for its grid after it, so the arrows reach the grid. Escape still reaches the card (keys propagate up).
    function focusGrid() { if (grid.visible) grid.forceActiveFocus() }
    Component.onCompleted: {
        scheduleReset()
        later(focusGrid)
    }
    Component.onDestruction: gate.open = false
    onShowGridChanged: if (showGrid && !search.activeFocus) later(focusGrid)
    onQueryChanged: scheduleReset()
    onSortChanged: scheduleReset()
    onSeedChanged: if (sort === "random") scheduleReset()
    onFolderChanged: scheduleReset()
    onOnlyLooksChanged: scheduleReset()
    onLoadedChanged: if (loaded) scheduleReset()
    onInstalledChanged: if (installed) scheduleReset()
    onLibraryCountChanged: scheduleReset()
    onTotalChanged: if (grid.currentIndex >= total) grid.currentIndex = Math.max(0, total - 1)

    // ---- the theme preview (dry run; debounced while the selection moves) -----------------------
    Timer {
        id: previewDebounce
        interval: 160
        onTriggered: picker.runPreview()
    }
    function queuePreview() { previewDebounce.restart() }
    function runPreview() {
        var row = picker.selectedRow
        if (!row || !row.path || !picker.showGrid) {
            previewToken++
            themePreview = null
            previewError = ""
            previewBusy = false
            return
        }
        var g = gate
        var token = ++previewToken
        previewBusy = true
        Store.act("wallpaper.preview", { path: row.path, scheme: picker.previewScheme }, function (done, err) {
            if (!g.open || token !== picker.previewToken) return
            picker.previewBusy = false
            if (err) { picker.themePreview = null; picker.previewError = err.msg; return }
            picker.previewError = ""
            picker.themePreview = (done && done.data) || null
        })
    }
    onPreviewSchemeChanged: queuePreview()

    // ---- actions ------------------------------------------------------------------------------
    // Where a transition starts: the tile's centre, in output-local px. The Stage card sits centred under the bar,
    // so the window's offset is taken from the screen (an approximation until the Stage passes its origin).
    function originOf(item) {
        var win = Window.window
        if (!win || Screen.width <= 0) return null
        var p = item.mapToItem(null, item.width / 2, item.height / 2)
        var ox = (Screen.width - win.width) / 2
        return { x: Math.round(ox + p.x), y: Math.round(Theme.barH + p.y) }
    }
    function setWallpaper(path, allOutputs, withThemeNow, origin) {
        var args = { path: path, theme: withThemeNow === true }
        if (!allOutputs && target !== "") args.output = target
        if (origin) args.origin = origin
        var g = gate
        Store.act("wallpaper.set", args, function (done, err) {
            if (!g.open) return
            errorKey = err ? err.msg : ""
            // The theme follows the picture: the palette source and the scheme the preview showed (config intents,
            // as the Settings page sends them). A refused choice shows in the footer from the theme document.
            if (!err && withThemeNow === true) followTheme(previewScheme, "wallpaper")
        })
    }
    function followTheme(scheme, variant) {
        if (scheme !== configScheme) Store.intent("theme.colors.scheme", scheme, "wallpaper")
        if (variant !== configPalette) Store.intent("theme.colors.palette", variant, "wallpaper")
    }
    // A picture the picker can use: the backend answers and the file reads (a broken tile is shown, not applied).
    function canUse(row) {
        return backendUp && row !== null && row !== undefined && row.error === undefined && row.path !== undefined
    }
    function applyRow(row, allOutputs, withThemeNow, origin) {
        if (canUse(row)) setWallpaper(row.path, allOutputs, withThemeNow, origin)
    }
    function toggleLook(row) {
        if (!row || !row.path || row.error !== undefined) return
        var g = gate
        Store.act("wallpaper.favourite", { image: row.path, scheme: previewScheme, variant: "wallpaper" },
            function (done, err) { if (g.open) errorKey = err ? err.msg : "" })
    }
    function applyLook(look) {
        var args = { path: look.image, theme: true }
        if (target !== "") args.output = target
        var g = gate
        Store.act("wallpaper.set", args, function (done, err) {
            if (!g.open) return
            errorKey = err ? err.msg : ""
            if (!err) followTheme(look.scheme === "light" ? "light" : "dark", look.variant || "wallpaper")
        })
    }
    // A deferred call that does nothing once the panel is gone (the closure holds the gate, not the panel).
    function later(fn) {
        var g = gate
        Qt.callLater(function () { if (g.open) fn() })
    }
    function restartBackend() {
        var g = gate
        Store.act("wallpaper.backend.restart", {}, function (done, err) {
            if (!g.open) return
            picker.errorKey = err ? err.msg : ""
        })
    }
    function clearCache() {
        var g = gate
        Store.act("wallpaper.cache.clear", {}, function () {
            if (g.open) picker.resetRows()
        })
    }
    function shuffle() {
        seed = Math.floor(Math.random() * 1000000) + 1
        sort = "random"
    }

    // ---- header: the backend and the rotation, in one line -------------------------------------
    Text {
        id: title
        anchors.top: parent.top
        anchors.left: parent.left
        text: I18n.tr("mod-wallpaper.title")
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
    }
    Text {
        id: status
        anchors.baseline: title.baseline
        anchors.left: title.right
        anchors.right: parent.right
        anchors.leftMargin: Theme.gap
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

    // ---- targets: every output, one output, and span greyed with its reason ---------------------
    Flow {
        id: targets
        anchors.top: title.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.gap
        spacing: Theme.xs
        Chip {
            id: allChip
            text: I18n.tr("mod-wallpaper.target.all")
            fg: picker.target === "" ? Theme.fgOnAccent : Theme.fg
            bg: picker.target === "" ? Theme.accent : Theme.containerHigh
            edge: picker.target === "" ? Theme.accent : Theme.outline
            activeFocusOnTab: true
            Keys.onReturnPressed: picker.target = ""
            Keys.onEnterPressed: picker.target = ""
            Accessible.role: Accessible.Button
            Accessible.name: text
            Accessible.checkable: true
            Accessible.checked: picker.target === ""
            MouseArea { anchors.fill: parent; onClicked: picker.target = "" }
            FocusRing { anchors.fill: parent; corner: height / 2; shown: allChip.activeFocus }
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
                height: Math.max(Theme.controlH - 4, 24)
                radius: height / 2
                color: chosen ? Theme.accent : Theme.containerHigh
                border.width: 1
                border.color: chosen ? Theme.accent : Theme.outline
                activeFocusOnTab: true
                Keys.onReturnPressed: picker.target = modelData
                Keys.onEnterPressed: picker.target = modelData
                Accessible.role: Accessible.Button
                Accessible.name: modelData
                Accessible.checkable: true
                Accessible.checked: chosen
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
                        width: 24
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter
                        source: outChip.out.path ? picker.fileUrl(outChip.out.path) : ""
                        sourceSize.width: 48
                        sourceSize.height: 28
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== ""
                    }
                    Text {
                        height: outChip.height - 4
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
            id: spanChip
            text: I18n.tr("mod-wallpaper.target.span")
            fg: Theme.outline
            edge: Theme.outline
            Accessible.role: Accessible.Button
            Accessible.name: text
            Accessible.description: I18n.tr("mod-wallpaper.target.span.reason")
        }
        // Why Span is greyed: the reason the backend gives (docs/ux/wallpaper.md, "Per output").
        Text {
            color: Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("mod-wallpaper.target.span.short")
        }
    }

    // ---- folders: the breadcrumb (All › root › sub …) and the folders under the current one ----------
    // One row of chips, all keyboard-reachable: Up from the first grid row lands on the current crumb, Left and
    // Right move along the row, Return opens a folder, Down goes back to the grid.
    Flow {
        id: crumbRow
        anchors.top: targets.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.xs
        spacing: Theme.xs
        Repeater {
            id: chips
            model: picker.chipsWithLooks()
            delegate: Rectangle {
                id: chip
                required property var modelData
                required property int index
                readonly property bool here: modelData.here === true
                readonly property bool isSub: modelData.kind === "sub"
                height: 22
                width: chipText.implicitWidth + Theme.gap * 1.5
                radius: height / 2
                // The current folder is filled, the others are outlined: where the picker is shows at a glance.
                color: here ? Theme.containerHigh : "transparent"
                border.width: 1
                border.color: here ? Theme.dim : (isSub ? Theme.dim : Theme.outline)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Accessible.checkable: here
                Accessible.checked: here
                Keys.onReturnPressed: picker.activateChipAndFocus(chip.modelData)
                Keys.onEnterPressed: picker.activateChipAndFocus(chip.modelData)
                Keys.onLeftPressed: if (chip.index > 0) chips.itemAt(chip.index - 1).forceActiveFocus()
                Keys.onRightPressed: if (chip.index < chips.count - 1) chips.itemAt(chip.index + 1).forceActiveFocus()
                Keys.onDownPressed: picker.focusGrid()
                FocusRing { anchors.fill: parent; corner: chip.radius; shown: chip.activeFocus }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    color: chip.here ? Theme.fg : Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: chip.modelData.label
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: picker.activateChipAndFocus(chip.modelData)
                }
            }
        }
    }

    // ---- toolbar: search, sort, looks, shuffle --------------------------------------------------
    Row {
        id: toolbar
        anchors.top: crumbRow.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.gap
        spacing: Theme.xs
        Rectangle {
            id: searchBox
            width: Math.max(96, parent.width - sortName.width - sortNewest.width - sortRandom.width - parent.spacing * 3)
            height: Theme.controlH
            radius: Theme.rSm
            color: Theme.containerHigh
            border.width: search.activeFocus ? 1 : 0
            border.color: Theme.focusRing
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
                activeFocusOnTab: true
                onTextEdited: searchDebounce.restart()
                Keys.onEscapePressed: { text = ""; picker.query = ""; grid.forceActiveFocus() }
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
        }
        Timer {
            id: searchDebounce
            interval: 250
            onTriggered: picker.query = search.text
        }
        Button {
            id: sortName
            label: I18n.tr("mod-wallpaper.sort.name")
            primary: picker.sort === "name"
            onClicked: picker.sort = "name"
        }
        Button {
            id: sortNewest
            label: I18n.tr("mod-wallpaper.sort.newest")
            primary: picker.sort === "newest"
            onClicked: picker.sort = "newest"
        }
        Button {
            id: sortRandom
            label: I18n.tr("mod-wallpaper.random")
            primary: picker.sort === "random"
            enabled: picker.showGrid
            onClicked: picker.shuffle()
        }
    }

    // ---- footer: the error in effect, or the counts; cache and restart -------------------------
    Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(Theme.controlH, 24)
        Text {
            id: footerText
            anchors.left: parent.left
            anchors.right: footerButtons.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            color: (picker.errorKey !== "" || picker.doc.error || picker.themeErrorText() !== "") ? Theme.error : Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: {
                var err = picker.errorKey !== "" ? I18n.tr(picker.errorKey)
                    : (picker.doc.error && picker.doc.error.key ? I18n.tr(picker.doc.error.key) : picker.themeErrorText())
                if (err !== "") return err
                return picker.tr2("mod-wallpaper.footer", {
                    backend: picker.backend.id || "",
                    version: picker.backend.version || "",
                    outputs: picker.outputNames.length,
                    images: picker.libraryCount
                })
            }
        }
        Row {
            id: footerButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.xs
            Button {
                id: restartButton
                label: I18n.tr("mod-wallpaper.backend.restart")
                visible: picker.installed && picker.loaded && !picker.backendUp
                onClicked: picker.restartBackend()
            }
            Button {
                id: cacheButton
                label: I18n.tr("mod-wallpaper.cache.clear")
                enabled: picker.installed
                onClicked: picker.clearCache()
            }
        }
    }

    // The theme document's own refusal (a palette the pipeline cannot take), when the picture is in effect.
    function themeErrorText() {
        var e = themeDoc.error
        if (!e) return ""
        if (typeof e === "string") return I18n.tr(e)
        return e.key ? I18n.tr(e.key) : ""
    }

    // ---- preview: the selected picture, the theme it would give, and the one-step actions --------
    Item {
        id: preview
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: Theme.gap
        height: picker.showGrid && picker.selectedRow !== null ? previewCol.implicitHeight + Theme.gap : 0
        visible: height > 0
        Rectangle {
            // A hairline between the grid and the preview; the card stays the only frame.
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.outline
            opacity: 0.5
        }
        Column {
            id: previewCol
            anchors.top: parent.top
            anchors.topMargin: Theme.gap
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Theme.gap
            Row {
                spacing: Theme.gap
                width: parent.width
                Image {
                    id: previewImage
                    width: 104
                    height: 58
                    source: picker.selectedRow && picker.selectedRow.thumb ? picker.fileUrl(picker.selectedRow.thumb) : ""
                    sourceSize.width: 208
                    sourceSize.height: 116
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.outline
                        radius: Theme.rSm
                    }
                }
                Column {
                    width: parent.width - previewImage.width - Theme.gap
                    spacing: 3
                    Text {
                        width: parent.width
                        elide: Text.ElideMiddle
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: picker.selectedRow ? picker.selectedRow.name : ""
                    }
                    Row {
                        spacing: Theme.xs
                        Repeater {
                            model: picker.selectedRow && picker.selectedRow.palette ? picker.selectedRow.palette : []
                            delegate: Rectangle {
                                required property string modelData
                                width: 14
                                height: 14
                                radius: 3
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
                        visible: text !== ""
                        text: {
                            var r = picker.selectedRow
                            if (!r) return ""
                            var bits = []
                            if (r.pair) bits.push(I18n.tr("mod-wallpaper.pair." + r.pair.role))
                            if (r.on && r.on.length > 0) bits.push(I18n.tr("mod-wallpaper.on") + " " + r.on.join(", "))
                            if (r.mono === true) bits.push(I18n.tr("mod-wallpaper.mono.warning"))
                            return bits.join(" · ")
                        }
                    }
                }
            }

            // The theme diff: each role now (left) and as this picture would make it (right), in the chosen scheme.
            Row {
                id: diffRow
                width: parent.width
                spacing: Theme.gap
                Text {
                    id: diffHead
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("mod-wallpaper.theme.diff")
                    width: 58
                    elide: Text.ElideRight
                }
                Repeater {
                    model: [
                        { role: "accent", label: "mod-wallpaper.role.accent", now: "color.accent" },
                        { role: "surface", label: "mod-wallpaper.role.surface", now: "color.surface" },
                        { role: "on_surface", label: "mod-wallpaper.role.text", now: "color.on_surface" },
                        { role: "secondary", label: "mod-wallpaper.role.secondary", now: "color.secondary" }
                    ]
                    delegate: Column {
                        id: pair
                        required property var modelData
                        readonly property string nowHex: String(picker.theme.tok(pair.modelData.now, "#777777"))
                        readonly property string nextHex: picker.themePreview && picker.themePreview.roles
                            ? String(picker.themePreview.roles[pair.modelData.role] || "") : ""
                        spacing: 2
                        Row {
                            spacing: 2
                            Rectangle {
                                width: 14; height: 14; radius: 3
                                color: pair.nowHex
                                border.width: 1; border.color: Theme.outline
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.dim
                                font.pixelSize: Theme.fsCaption
                                text: "→"
                            }
                            Rectangle {
                                width: 14; height: 14; radius: 3
                                color: pair.nextHex !== "" ? pair.nextHex : "transparent"
                                border.width: 1; border.color: Theme.outline
                                opacity: picker.previewBusy ? 0.4 : 1
                            }
                        }
                        Text {
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(pair.modelData.label)
                        }
                    }
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: picker.previewError !== "" ? Theme.error : Theme.dim
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: {
                    if (picker.previewError !== "") return I18n.tr(picker.previewError)
                    if (picker.previewBusy || !picker.previewCurrent) return I18n.tr("mod-wallpaper.theme.previewing")
                    return I18n.tr("mod-wallpaper.theme.axes")
                }
            }

            // The actions: the theme switch and the scheme, then Apply, Wallpaper only, and the look (★).
            Flow {
                width: parent.width
                spacing: Theme.xs
                Chip {
                    id: themeSwitch
                    text: picker.withTheme ? I18n.tr("mod-wallpaper.theme.on") : I18n.tr("mod-wallpaper.theme.off")
                    fg: picker.withTheme ? Theme.fgOnAccent : Theme.dim
                    bg: picker.withTheme ? Theme.accent : Theme.surface
                    edge: picker.withTheme ? Theme.accent : Theme.outline
                    activeFocusOnTab: true
                    Keys.onReturnPressed: picker.withTheme = !picker.withTheme
                    Keys.onEnterPressed: picker.withTheme = !picker.withTheme
                    Keys.onSpacePressed: picker.withTheme = !picker.withTheme
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: I18n.tr("mod-wallpaper.theme.switch")
                    Accessible.checked: picker.withTheme
                    MouseArea { anchors.fill: parent; onClicked: { picker.withTheme = !picker.withTheme; themeSwitch.forceActiveFocus() } }
                    FocusRing { anchors.fill: parent; corner: height / 2; shown: themeSwitch.activeFocus }
                }
                Chip {
                    id: schemeDark
                    text: I18n.tr("mod-wallpaper.scheme.dark")
                    fg: picker.previewScheme === "dark" ? Theme.fgOnAccent : Theme.dim
                    bg: picker.previewScheme === "dark" ? Theme.accent : Theme.surface
                    edge: picker.previewScheme === "dark" ? Theme.accent : Theme.outline
                    activeFocusOnTab: true
                    Keys.onReturnPressed: picker.schemeChoice = "dark"
                    Keys.onEnterPressed: picker.schemeChoice = "dark"
                    Accessible.role: Accessible.Button
                    Accessible.name: text
                    MouseArea { anchors.fill: parent; onClicked: picker.schemeChoice = "dark" }
                    FocusRing { anchors.fill: parent; corner: height / 2; shown: schemeDark.activeFocus }
                }
                Chip {
                    id: schemeLight
                    text: I18n.tr("mod-wallpaper.scheme.light")
                    fg: picker.previewScheme === "light" ? Theme.fgOnAccent : Theme.dim
                    bg: picker.previewScheme === "light" ? Theme.accent : Theme.surface
                    edge: picker.previewScheme === "light" ? Theme.accent : Theme.outline
                    activeFocusOnTab: true
                    Keys.onReturnPressed: picker.schemeChoice = "light"
                    Keys.onEnterPressed: picker.schemeChoice = "light"
                    Accessible.role: Accessible.Button
                    Accessible.name: text
                    MouseArea { anchors.fill: parent; onClicked: picker.schemeChoice = "light" }
                    FocusRing { anchors.fill: parent; corner: height / 2; shown: schemeLight.activeFocus }
                }
            }
            Flow {
                width: parent.width
                spacing: Theme.xs
                Button {
                    id: applyButton
                    label: picker.target === "" ? I18n.tr("mod-wallpaper.apply.all") : I18n.tr("mod-wallpaper.apply")
                    primary: true
                    enabled: picker.canUse(picker.selectedRow)
                    onClicked: picker.applyRow(picker.selectedRow, false, picker.withTheme, null)
                }
                Button {
                    id: onlyButton
                    label: I18n.tr("mod-wallpaper.apply.wallpaper_only")
                    enabled: picker.canUse(picker.selectedRow)
                    onClicked: picker.applyRow(picker.selectedRow, false, false, null)
                }
                Button {
                    id: lookButton
                    label: picker.selectedRow && picker.selectedRow.favourite === true
                        ? I18n.tr("mod-wallpaper.favourite.remove") : I18n.tr("mod-wallpaper.favourite.add")
                    enabled: picker.canUse(picker.selectedRow)
                    onClicked: picker.toggleLook(picker.selectedRow)
                }
            }
        }
    }

    // ---- body: the grid, or the state that replaces it ------------------------------------------
    Item {
        id: body
        anchors.top: toolbar.bottom
        anchors.bottom: preview.visible ? preview.top : footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.gap
        anchors.bottomMargin: Theme.gap
        clip: true

        // The empty and error states (docs/ux/wallpaper.md "States"): each says what to do next.
        Column {
            id: emptyState
            visible: !picker.showGrid
            anchors.centerIn: parent
            width: parent.width - Theme.pad * 2
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
                    if (picker.looks.length === 0 && picker.onlyLooks) return I18n.tr("mod-wallpaper.empty.looks.title")
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
                    if (picker.looks.length === 0 && picker.onlyLooks) return I18n.tr("mod-wallpaper.empty.looks.hint")
                    return I18n.tr("mod-wallpaper.empty.filter.hint")
                }
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: picker.loaded && picker.installed && !picker.backendUp
                label: I18n.tr("mod-wallpaper.backend.restart")
                onClicked: picker.restartBackend()
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: picker.loaded && picker.installed && picker.onlyLooks
                label: I18n.tr("mod-wallpaper.favourites.all")
                onClicked: picker.onlyLooks = false
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
            highlightMoveDuration: Theme.quickMs
            model: picker.total
            cellWidth: Math.floor(width / picker.columns)
            cellHeight: Math.round((cellWidth - 8) * 9 / 16) + 30
            boundsBehavior: Flickable.StopAtBounds
            Accessible.role: Accessible.List
            Accessible.name: I18n.tr("mod-wallpaper.title")

            onCurrentIndexChanged: picker.queuePreview()
            onCountChanged: picker.queuePreview()
            Connections {
                target: picker
                function onRowsRevChanged() { picker.queuePreview() }
            }

            Keys.onPressed: function (event) {
                var row = picker.selectedRow
                var mods = event.modifiers
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (row && row.path) {
                        var all = (mods & Qt.ShiftModifier) !== 0
                        var onlyWallpaper = (mods & Qt.ControlModifier) !== 0
                        picker.applyRow(row, all, picker.withTheme && !onlyWallpaper, picker.originOf(grid.currentItem || grid))
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_F) {
                    picker.toggleLook(row)
                    event.accepted = true
                } else if (event.key === Qt.Key_T) {
                    picker.withTheme = !picker.withTheme
                    event.accepted = true
                } else if (event.key === Qt.Key_R) {
                    picker.shuffle()
                    event.accepted = true
                } else if (event.key === Qt.Key_Backspace) {
                    picker.upFolder()
                    event.accepted = true
                } else if (event.key === Qt.Key_Up && grid.currentIndex < picker.columns) {
                    // The first row: Up goes to the folder row, Down comes back.
                    picker.focusFolderRow()
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
                    border.width: cell.current ? 2 : (tileHover.hovered ? 1 : 0)
                    border.color: cell.current ? Theme.accent : Theme.outline
                    clip: true
                    Accessible.role: Accessible.ListItem
                    Accessible.name: cell.row
                        ? cell.row.name + (cell.row.favourite === true ? ", " + I18n.tr("mod-wallpaper.favourite.mark") : "")
                            + (cell.row.on && cell.row.on.length > 0 ? ", " + I18n.tr("mod-wallpaper.on") + " " + cell.row.on.join(", ") : "")
                        : ""
                    Accessible.checkable: true
                    Accessible.checked: cell.current

                    Image {
                        id: thumb
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: parent.height - 22
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
                    // Badges: a look (★), the light or dark half of a pair, and the output(s) showing it.
                    Row {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 4
                        spacing: 3
                        Chip {
                            visible: cell.row !== null && cell.row.pair !== undefined
                            text: cell.row && cell.row.pair ? I18n.tr("mod-wallpaper.pair." + cell.row.pair.role) : ""
                            fg: Theme.fg
                            bg: Theme.surfaceAlpha
                            edge: Theme.outline
                        }
                    }
                    Row {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        spacing: 3
                        Chip {
                            visible: cell.row !== null && cell.row.favourite === true
                            text: "★"
                            fg: Theme.accent
                            bg: Theme.surfaceAlpha
                            edge: Theme.accent
                        }
                        Chip {
                            visible: cell.row !== null && cell.row.on !== undefined && cell.row.on.length > 0
                            text: cell.row && cell.row.on ? "● " + cell.row.on.join(" ") : ""
                            fg: Theme.fg
                            bg: Theme.surfaceAlpha
                            edge: Theme.outline
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
                            return cell.row.name
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
                        anchors.centerIn: thumb
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
                    HoverHandler { id: tileHover }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            grid.currentIndex = cell.index
                            grid.forceActiveFocus()
                        }
                        onDoubleClicked: {
                            grid.currentIndex = cell.index
                            if (cell.row && cell.row.path)
                                picker.applyRow(cell.row, false, picker.withTheme, picker.originOf(tile))
                        }
                    }
                }
            }
        }
    }
}
