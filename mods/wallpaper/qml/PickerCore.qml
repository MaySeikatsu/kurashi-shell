import QtQuick
import qs.core
import qs.components

// What both wallpaper pickers are made of (W99, rule 10): the mod's own Stage card (Panel.qml) and the appearance menu's
// Wallpaper pane (Picker.qml) are this item with a layout of the shared pieces (Targets, FolderChips, Crumbs, SortChips,
// SearchBox, Tile, PreviewPane, RotationRow, EmptyState, Wallhaven). A view: it subscribes to `mod.wallpaper` and
// `config`, pages the library with `wallpaper.thumbs` (thumbnails, palette chips, pairs and subfolders are the daemon's),
// asks `wallpaper.preview` for the theme a picture would give (a dry run), sends `wallpaper.*` actions and config writes.
// The pieces reach it as `host`. The layout sets `view` (its GridView) and answers `wantsFolderRow` and `wantsSearch`.
// Keys in the grid (`gridKey`): arrows move, Enter applies (with the theme while the theme switch is on), Ctrl+Enter the
// picture alone, Shift+Enter every output, F keeps the look, T the theme switch, R shuffles, Backspace goes up a folder,
// / searches, Up from the first row reaches the folder row.
Item {
    id: core
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    property Item view: null            // the layout's GridView
    signal wantsFolderRow()             // Up from the grid's first row
    signal wantsSearch()                // `/` in the grid

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
    readonly property var libFolders: (doc.library && doc.library.folders) || []
    readonly property int libraryCount: (doc.library && doc.library.count) || 0
    readonly property var rotationState: doc.rotation || ({})
    readonly property var looks: doc.favourites || []
    readonly property var themeDoc: Store.docs["theme"] || ({})
    readonly property var configValues: (Store.docs["config"] && Store.docs["config"].values) || ({})
    function cfg(key, d) { var p = configValues[key]; return p && p.value !== undefined ? p.value : d }
    readonly property string configMode: String(cfg("theme.colors.scheme", ""))
    readonly property string configScheme: {
        if (configMode === "light" || configMode === "dark") return configMode
        return themeDoc.appearance && themeDoc.appearance.scheme_effective === "light" ? "light" : "dark"
    }
    // I455: the preview extracts as the theme would.
    readonly property string configExtraction: String(cfg("theme.colors.extraction", ""))
    readonly property string configPalette: String(cfg("theme.colors.palette", ""))
    readonly property bool themeFollowsWallpaper: configPalette === "wallpaper"
    // The mod's own settings the pickers change at once (the folders, rotation; Wallhaven on or off).
    readonly property var folderList: { var v = cfg("mods.wallpaper.folders", []); return Array.isArray(v) ? v : [] }
    readonly property bool wallhavenOn: cfg("mods.wallpaper.wallhaven", true) === true
    readonly property int rotate: Number(cfg("mods.wallpaper.rotate", 0))
    readonly property string rotateOrder: String(cfg("mods.wallpaper.rotate_order", "alphabetical"))

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
    // The last Apply asked the theme to follow the picture and the config write came back accepted.
    property bool themeRequested: false
    property string errorKey: ""        // the last refused request, translated when shown
    property var subfolders: []         // folders under `folder`, from the last page (name, path, count)
    property real cacheBytes: -1        // the thumbnail cache's size from the first page; -1 while not known
    property string tab: "library"      // library | wallhaven
    readonly property bool onLibrary: tab === "library"
    onWallhavenOnChanged: if (!wallhavenOn) tab = "library"
    property bool adding: false         // the folder row's path field is open

    readonly property int pageSize: 48
    property var rowCache: ({})         // library index -> row, as wallpaper.thumbs returns it
    property var pending: ({})          // page offset -> true while its request is out
    property int total: 0
    property int rowsRev: 0             // bumped when rows arrive: delegates re-read their row
    property int requestToken: 0        // a filter change makes older answers stale
    property bool resetQueued: false    // one reset per turn, however many filters change at once
    // I32: the first page was asked for with these filters and has not been reset since (a document update while the
    // picker opens must not ask for it again).
    property string pagedWith: ""

    // Closed when the picker is destroyed: the callbacks below capture this object, never the picker itself.
    property var gate: ({ open: true })
    readonly property var selectedRow: rowAt(view ? view.currentIndex : -1)
    readonly property bool showGrid: loaded && installed && total > 0
    // Columns of about 220 px where there is room (I538), 160 px in a narrow card; never fewer than `least`.
    function columnsFor(w, least) { return Math.max(least, Math.floor(w / (w >= 900 ? 220 : 160))) }
    readonly property int columns: view && view.cellWidth > 0 ? Math.max(1, Math.round(view.width / view.cellWidth)) : 1

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
    function fileUrl(p) { return "file://" + String(p).split("/").map(encodeURIComponent).join("/") }
    function baseName(p) { var parts = String(p).split("/"); return parts[parts.length - 1] || String(p) }
    // The cache's size: KiB below a MiB, then MiB (the unit is the same in every language).
    function sizeText(bytes) {
        return bytes < 1048576 ? Math.round(bytes / 1024) + " KiB" : (bytes / 1048576).toFixed(1) + " MiB"
    }
    function rowAt(i) {
        core.rowsRev   // read, so a delegate's binding follows the pages as they arrive
        return (i >= 0 && rowCache[i] !== undefined) ? rowCache[i] : null
    }
    function pageFor(i) { return Math.floor(i / pageSize) * pageSize }
    // A deferred call that does nothing once the picker is gone (the closure holds the gate, not the picker).
    function later(fn) { var g = gate; Qt.callLater(function () { if (g.open) fn() }) }

    // ---- folders: the configured ones (the folder row) and the breadcrumb under the chosen one --------------
    // A configured folder's path as the document names it (expanded), by place; the configured text otherwise.
    function folderPath(i) { return i < libFolders.length && libFolders[i].path ? libFolders[i].path : folderList[i] }
    function folderAvailable(i) { return i < libFolders.length ? libFolders[i].available === true : true }
    // The configured folder a path lies in (the breadcrumb's first crumb), "" when none does.
    function rootOf(p) {
        for (var i = 0; i < libFolders.length; i++) {
            var f = libFolders[i].path
            if (p === f || p.indexOf(f + "/") === 0) return f
        }
        return ""
    }
    readonly property string folderRoot: folder === "" ? "" : rootOf(folder)
    // The crumbs under the chosen configured folder (its own chip is in the folder row), then the folders under the
    // current one. Each: {kind, label, path, here}; `here` marks the current folder.
    function crumbModel() {
        var out = []
        if (folder === "" || folderRoot === "") return out
        if (folder !== folderRoot) {
            out.push({ kind: "crumb", label: baseName(folderRoot), path: folderRoot, here: false })
            var rest = folder.substring(folderRoot.length + 1).split("/")
            var acc = folderRoot
            for (var j = 0; j < rest.length; j++) {
                acc = acc + "/" + rest[j]
                out.push({ kind: "crumb", label: rest[j], path: acc, here: acc === folder })
            }
        }
        for (var k = 0; k < subfolders.length; k++)
            out.push({ kind: "sub", label: subfolders[k].name + "  " + subfolders[k].count, path: subfolders[k].path, here: false })
        return out
    }
    function upFolder() {
        if (folder === "") return
        var up = folder.substring(0, folder.lastIndexOf("/"))
        folder = rootOf(up) === "" ? "" : up
    }
    function setFolders(list) {
        var g = gate
        Store.apply([{ set: "mods.wallpaper.folders", value: list }], function (errs) {
            if (g.open) core.errorKey = errs && errs.length > 0 ? (errs[0].code || "") : ""
        })
    }
    function addFolder(path) {
        var p = String(path).trim()
        adding = false
        if (p !== "" && folderList.indexOf(p) < 0) setFolders(folderList.concat([p]))
    }
    function removeFolder(i) {
        var list = folderList.slice()
        var gone = folderPath(i)
        list.splice(i, 1)
        if (folder !== "" && rootOf(folder) === gone) folder = ""
        setFolders(list)
    }
    function setRotate(min) { Store.apply([{ set: "mods.wallpaper.rotate", value: min }], null) }
    function setOrder(o) { Store.apply([{ set: "mods.wallpaper.rotate_order", value: o }], null) }

    // ---- paging: one reset per turn, one request per page -------------------------------------
    function scheduleReset() {
        if (resetQueued) return
        resetQueued = true
        later(function () { core.resetQueued = false; core.resetRows() })
    }
    function filterKey() {
        return JSON.stringify([query, sort, seed, onlyLooks, folder, libraryCount, folderList, loaded && installed])
    }
    // The count stays until the new page answers: clearing it hid the grid for a turn (a flicker, and focus lost from
    // the search field while typing).
    function resetRows() {
        var key = filterKey()
        // I32: the same filters as the page out or in hand: nothing to ask again (the documents arriving while the
        // picker opens each scheduled a reset, and each reset asked for the first page anew).
        if (key === pagedWith) return
        rowCache = ({})
        pending = ({})
        requestToken++
        rowsRev++
        subfolders = []
        if (view) view.currentIndex = 0
        pagedWith = ""
        firstPageOut = false
        if (installed && loaded) { pagedWith = key; firstPageOut = true; requestPage(0) }
    }
    // The first page of these filters is still out (the daemon makes the thumbnails it lacks first): the grid's state
    // says so instead of "nothing matches".
    property bool firstPageOut: false
    // Rows again with the same filters (the cache was cleared): the reset may not skip it.
    function reload() { pagedWith = ""; resetRows() }
    function requestPage(offset) {
        if (pending[offset] === true) return
        var g = gate
        var token = requestToken
        pending[offset] = true
        Store.act("wallpaper.thumbs", {
            offset: offset, limit: pageSize, query: query, sort: sort, seed: seed,
            favourites: onlyLooks, folder: folder
        }, function (done, err) {
            if (!g.open || token !== core.requestToken) return
            delete pending[offset]
            if (offset === 0) firstPageOut = false
            if (err) { errorKey = err.msg; if (offset === 0) pagedWith = ""; return }
            var data = (done && done.data) || {}
            var rows = data.rows || []
            for (var i = 0; i < rows.length; i++) rowCache[offset + i] = rows[i]
            total = data.total || 0
            if (offset === 0) {
                subfolders = data.children || []
                // The first page carries the cache's size; a page without it leaves the size not known.
                cacheBytes = data.cache && data.cache.bytes !== undefined ? Number(data.cache.bytes) : -1
            }
            rowsRev++
        })
    }
    Component.onCompleted: scheduleReset()
    Component.onDestruction: gate.open = false
    onQueryChanged: scheduleReset()
    onSortChanged: scheduleReset()
    onSeedChanged: if (sort === "random") scheduleReset()
    onFolderChanged: scheduleReset()
    onOnlyLooksChanged: scheduleReset()
    onLoadedChanged: scheduleReset()
    onInstalledChanged: scheduleReset()
    onLibraryCountChanged: scheduleReset()
    onFolderListChanged: scheduleReset()
    onTotalChanged: if (view && view.currentIndex >= total) view.currentIndex = Math.max(0, total - 1)

    // ---- the theme preview (dry run; debounced while the selection moves) -----------------------
    Timer {
        id: previewDebounce
        interval: 160
        onTriggered: core.runPreview()
    }
    function queuePreview() { previewDebounce.restart() }
    function runPreview() {
        var row = core.selectedRow
        if (!row || !row.path || row.error !== undefined || !core.showGrid || !core.onLibrary) {
            previewToken++
            themePreview = null
            previewError = ""
            previewBusy = false
            return
        }
        var g = gate
        var token = ++previewToken
        previewBusy = true
        Store.act("wallpaper.preview", { path: row.path, scheme: core.previewScheme, extraction: core.configExtraction }, function (done, err) {
            if (!g.open || token !== core.previewToken) return
            core.previewBusy = false
            if (err) { core.themePreview = null; core.previewError = err.msg; return }
            core.previewError = ""
            core.themePreview = (done && done.data) || null
        })
    }
    onPreviewSchemeChanged: queuePreview()
    onSelectedRowChanged: queuePreview()
    onOnLibraryChanged: queuePreview()

    // ---- actions ------------------------------------------------------------------------------
    // Where a transition starts: the tile's centre, in output-local px. The window is taken as centred under the bar
    // (the Stage card and the launcher both are; an approximation until the host passes its origin).
    function originOf(item) {
        var win = core.Window.window
        if (!win || !item || Screen.width <= 0) return null
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
            themeRequested = false
            if (!err && withThemeNow === true) followTheme(previewScheme, "wallpaper")
        })
    }
    // A core setting the mod writes (its manifest `uses` names it): one config write. I135: these went out as protocol
    // intents, which the daemon has no handler for (it answers "unknown intent"), so the theme never followed.
    function intent(key, value, cb) { Store.apply([{ set: key, value: value }], cb) }
    // The theme follows the picture: the palette source and the scheme the preview showed. K55: a mode that follows the
    // system or the wallpaper is kept; only a picked dark or light follows the preview. A refusal shows in the footer.
    function followTheme(scheme, variant) {
        var g = gate
        var done = function (errs) {
            if (!g.open) return
            if (errs && errs.length > 0) core.errorKey = errs[0].code || ""
            else core.themeRequested = true
        }
        if ((configMode === "dark" || configMode === "light") && scheme !== configMode)
            intent("theme.colors.scheme", scheme, null)
        if (variant !== configPalette) intent("theme.colors.palette", variant, done)
        else done(null)
    }
    // A picture the picker can use: the backend answers and the file reads (a broken tile is shown, not applied).
    function canUse(row) {
        return backendUp && row !== null && row !== undefined && row.error === undefined && row.path !== undefined
    }
    function applyRow(row, allOutputs, withThemeNow, origin) {
        if (canUse(row)) setWallpaper(row.path, allOutputs, withThemeNow, origin)
    }
    function applySelected(allOutputs, onlyWallpaper, origin) {
        applyRow(selectedRow, allOutputs, withTheme && !onlyWallpaper, origin)
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
            themeRequested = false
            if (!err) followTheme(look.scheme === "light" ? "light" : "dark", look.variant || "wallpaper")
        })
    }
    function restartBackend() {
        var g = gate
        Store.act("wallpaper.backend.restart", {}, function (done, err) { if (g.open) core.errorKey = err ? err.msg : "" })
    }
    function clearCache() {
        var g = gate
        Store.act("wallpaper.cache.clear", {}, function () { if (g.open) core.reload() })
    }
    // The saved look of a picture (its image, scheme and variant), or null: the picker's one-click look. From the
    // favourites document, not the row (a row keeps its flag until the page is fetched again).
    function lookOf(row) {
        if (!row || !row.path) return null
        for (var i = 0; i < looks.length; i++) if (looks[i].image === row.path) return looks[i]
        return null
    }
    function isLook(row) { return lookOf(row) !== null }
    function applyLookOf(row) {
        var look = lookOf(row)
        if (look && canUse(row)) applyLook(look)
    }
    // The grid in a shuffled order (the sort), and one picture at random on the screens now (the rotation's Shuffle now).
    function shuffle() {
        seed = Math.floor(Math.random() * 1000000) + 1
        sort = "random"
    }
    function shuffleNow() {
        var g = gate
        var args = target !== "" ? { output: target } : {}
        Store.act("wallpaper.random", args, function (done, err) { if (g.open) core.errorKey = err ? err.msg : "" })
    }
    function focusGrid() { if (view && view.visible) view.forceActiveFocus() }

    // The keys of the grid (the layout's GridView calls this from Keys.onPressed).
    function gridKey(event) {
        var row = selectedRow
        var mods = event.modifiers
        var k = event.key
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            applySelected((mods & Qt.ShiftModifier) !== 0, (mods & Qt.ControlModifier) !== 0,
                originOf(view.currentItem || view))
        } else if (k === Qt.Key_F && mods === Qt.NoModifier) {
            toggleLook(row)
        } else if (k === Qt.Key_T && mods === Qt.NoModifier) {
            withTheme = !withTheme
        } else if (k === Qt.Key_R && mods === Qt.NoModifier) {
            shuffle()
        } else if (k === Qt.Key_Backspace && folder !== "") {
            upFolder()
        } else if (k === Qt.Key_Up && view.currentIndex < columns) {
            wantsFolderRow()
        } else if (k === Qt.Key_Slash) {
            wantsSearch()
        } else {
            return
        }
        event.accepted = true
    }

    // ---- what the pickers say -------------------------------------------------------------------
    function themeErrorText() {
        var e = themeDoc.error
        if (!e) return ""
        if (typeof e === "string") return I18n.tr(e)
        return e.key ? I18n.tr(e.key) : ""
    }
    // About the theme: the theme document's refusal, else that an Apply with the theme did not make it follow the
    // picture (the palette in effect is not `wallpaper`: held by another layer). Empty when there is nothing to say.
    function themeNote() {
        if (themeErrorText() !== "") return themeErrorText()
        if (themeRequested && configPalette !== "wallpaper") return I18n.tr("mod-wallpaper.theme.not_applied")
        return ""
    }
    // The line under the picker: the refused request, the mod's own error, the theme's note — else "".
    function problemText() {
        if (errorKey !== "") return I18n.tr(errorKey)
        if (doc.error && doc.error.key) return I18n.tr(doc.error.key)
        return themeNote()
    }
    readonly property bool allMissing: libFolders.length > 0 && libFolders.every(function (f) { return f.available !== true })
    // The state in place of the grid (docs/ux/wallpaper.md "States"): what it is, and what to do next.
    function emptyTitle() {
        if (!loaded) return I18n.tr("mod-wallpaper.loading")
        if (!installed) return I18n.tr("mod-wallpaper.empty.backend.title")
        if (folderList.length === 0) return I18n.tr("appearance-menu.wallpaper.none")
        if (allMissing) return I18n.tr("mod-wallpaper.empty.folder.missing.title")
        if (libraryCount === 0) return I18n.tr("mod-wallpaper.empty.library.title")
        if (firstPageOut) return I18n.tr("mod-wallpaper.thumbs.loading")
        if (looks.length === 0 && onlyLooks) return I18n.tr("mod-wallpaper.empty.looks.title")
        return I18n.tr("mod-wallpaper.empty.filter.title")
    }
    function emptyHint() {
        if (!loaded) return ""
        if (!installed) return I18n.tr("mod-wallpaper.empty.backend.hint")
        if (folderList.length === 0) return I18n.tr("appearance-menu.wallpaper.none.hint")
        if (allMissing) return tr2("mod-wallpaper.empty.folder.missing.hint", { path: libFolders[0].path })
        if (libraryCount === 0) return tr2("appearance-menu.wallpaper.empty.hint", { path: folderList.join(", ") })
        if (firstPageOut) return I18n.tr("mod-wallpaper.thumbs.loading.hint")
        if (looks.length === 0 && onlyLooks) return I18n.tr("mod-wallpaper.empty.looks.hint")
        return I18n.tr("mod-wallpaper.empty.filter.hint")
    }
    // The backend and the rotation in one line (the header's status).
    function statusText() {
        if (!loaded) return I18n.tr("mod-wallpaper.loading")
        if (!installed) return I18n.tr(backend.reason || "mod-wallpaper.backend.missing")
        var parts = []
        if (backendUp) parts.push(backend.id + (backend.version ? " " + backend.version : ""))
        else parts.push(I18n.tr(backend.reason || "mod-wallpaper.backend.down"))
        if (rotationState.on === true) parts.push(tr2("mod-wallpaper.rotating", { min: rotationState.interval_min }))
        else if (rotationState.paused === true) parts.push(I18n.tr("mod-wallpaper.rotation.paused"))
        else parts.push(I18n.tr("mod-wallpaper.rotation.off"))
        parts.push(tr2("appearance-menu.wallpaper.count", { n: libraryCount }))
        return parts.join(" · ")
    }
}
