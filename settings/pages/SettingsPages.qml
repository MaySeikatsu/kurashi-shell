import QtQuick
import "../core"
import "../components"

// Renders `schema.settings` rows for one page, or for every page matching a search query. A search hit shows its
// breadcrumb (page › section › label); choosing one emits jumpRequested, and so does a reason's link to the setting
// that controls a row. A page can reset the settings the user set on it (diff first), name its related pages (UX brief,
// settings 2 and 7), and a mod's page starts with its head (settings 5).
Flickable {
    id: p
    property string pageId: ""
    property string query: ""
    property bool showAdvanced: false
    property string output: ""
    // byKeyboard: the jump came from the keyboard (a breadcrumb or a search hit), so the focus goes to the row's control.
    signal jumpRequested(string targetPage, var row, bool byKeyboard)
    signal pageRequested(string pageId)

    readonly property bool searching: query.trim() !== ""
    // The page's title, through I18n.pageTitle (a mod's page reads "Mods › <name>"). The strings are read so the title
    // is re-evaluated when they arrive.
    readonly property string heading: {
        var tr = I18n.strings
        var ps = Store.schema.pages || []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].id === p.pageId) return I18n.pageTitle(ps[i].id, ps[i].label)
        return ""
    }
    // The mod a mod page is for (the daemon's `mod` id, K25), "" on a core page: its head carries the switch.
    readonly property string modId: {
        var ps = Store.schema.pages || []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].id === p.pageId) return ps[i].mod || ""
        return ""
    }
    // The page structure the rows are built from: pages, sections and rows as the schema names them, but replaced only when
    // one of those is added, removed or renamed (structureOf). The daemon re-publishes `schema.settings` after a change (a
    // reordered choice list, say); a value change must not rebuild the rows, or the focus on a row is lost. Each row reads
    // its own schema row live (SettingRow.rowKey), so the new values show without a rebuild.
    property var structure: []
    property string structureSig: ""
    function structureOf(pages) {
        return JSON.stringify(pages.map(function (pg) {
            return [pg.id, pg.label, pg.mod !== undefined ? pg.mod : "", pg.sections.map(function (s) {
                return [s.id, s.label, s.rows.map(function (r) { return [r.key, r.label, r.help || "", !!r.advanced] })]
            })]
        }))
    }
    function refreshStructure() {
        var pages = Store.schema.pages || []
        var sig = structureOf(pages)
        if (sig !== structureSig) {
            structureSig = sig
            structure = pages
        }
    }
    Component.onCompleted: refreshStructure()
    Connections {
        target: Store
        function onSchemaChanged() { p.refreshStructure() }
    }

    // Related pages (UX brief, settings 7): the pages whose settings act on this one's, when they exist.
    readonly property var relatedPages: {
        var m = { island: ["notifications"], notifications: ["island"], appearance: ["accessibility"],
                  accessibility: ["appearance"], bar: ["appearance"] }
        var ps = p.structure
        return (m[p.pageId] || []).filter(function (id) {
            return ps.some(function (x) { return x.id === id })
        })
    }
    // The reset ops for every setting the user set on this page (one change when confirmed); none while searching.
    readonly property var userOps: {
        Store.config
        if (p.searching) return []
        return Store.userSetEntries(p.pageId).map(function (e) { return Store.resetOp(e.key, e.output) })
    }

    // Each section is a card with its icon (K48 (5), I104): by section id, or `page.section` where a page's section
    // needs its own; a mod's section gets the puzzle piece, any other the sliders. Display only: no key is named here.
    readonly property var sectionIcons: ({
        layout: "view_quilt", colors: "palette", shape: "rounded_corner", material: "blur_on", motion: "animation",
        typography: "text_fields", modes: "accessibility_new", main: "toggle_on", clock: "schedule",
        server: "notifications", apps: "apps", widgets: "widgets", idle: "bedtime", night_light: "nightlight",
        recorder: "screen_record", dock: "dock_to_bottom", texture: "texture", light: "light_mode",
        pen: "ink_pen", settings_app: "web_asset", shortcuts: "keyboard"
    })
    function sectionIcon(pageId, id) {
        return sectionIcons[pageId + "." + id] || sectionIcons[id] || (pageId.indexOf("mods.") === 0 ? "extension" : "tune")
    }
    // A document a row shows beside it (the one place Settings does): row key -> component. The theme export says where
    // each app's file went and what the app still needs (K49).
    readonly property var extras: ({ "theme.export": cThemeExport, "theme.colors.scheme": cSchemeStatus,
                                       "sidebar.bar_buttons": cSidebarOpen, "theme.texture.kind": cTextureCards,
                                       "theme.light.mode": cLightDial, "theme.colors.ink": cInkSwatches,
                                       "theme.light.color": cLightSwatches, "theme.material.shadow": cShadowPreview,
                                       "theme.texture.wallpaper.kind": cWallpaperCards, "keys.write": cKeysStatus })
    // Extras that are the row's own picker (every offer, keyboard as a radio group): they take the place of the row's
    // dropdown (SettingRow.picker), with the provenance line under them.
    readonly property var pickers: ({ "theme.texture.kind": true, "theme.colors.ink": true, "theme.light.color": true,
                                      "theme.texture.wallpaper.kind": true })
    // A document shown only while a switch is on (key -> the bool key): the wallpaper's own material cards (K61) show
    // while "Own material for the wallpaper" is on, and leave the row as a plain dropdown otherwise.
    readonly property var extraWhen: ({ "theme.texture.wallpaper.kind": "theme.texture.wallpaper.own" })
    // The picker that stands in for a row's control, or null (the generic control). A row whose schema control is
    // "shortcut" (K64: each `keys.*` shortcut) is recorded by keys, not typed; the schema says which rows those are.
    function pickerOf(key) {
        var r = Store.rowOf(key)
        if (r && r.row.control === "shortcut") return cShortcut
        return p.pickers[key] ? (p.extraOf(key) ?? null) : null
    }
    function extraOf(key) {
        var when = p.extraWhen[key]
        // On and in effect: a switch that is on but inert (the wallpaper's own material with the scope "shell") hides them too.
        var on = when === undefined ? null : Store.prov(when, "")
        if (when !== undefined && (!on || on.value !== true || on.reason === "settings.inert.requires"))
            return undefined
        return p.extras[key]
    }
    // The appearance blocks' icons, by the pack kind their row picks (W29). Display only.
    readonly property var packIcons: ({ styles: "style", looks: "category", palettes: "palette" })
    // Rows a pack block shows with it (K53 amendment): light or dark sits with the palette, as the palette cards are drawn
    // in it. Display only: the row keeps its own schema row, provenance and reset.
    readonly property var packCompanions: ({ palettes: ["theme.colors.scheme"] })
    Component { id: cThemeExport; ThemeExportStatus {} }
    Component { id: cSchemeStatus; SchemeStatus {} }
    Component { id: cSidebarOpen; SidebarOpen {} }
    Component { id: cTextureCards; TextureCards {} }
    Component { id: cLightDial; LightDial {} }
    Component { id: cInkSwatches; InkSwatches {} }
    Component { id: cLightSwatches; LightSwatches {} }
    Component { id: cShadowPreview; ShadowPreview {} }
    Component { id: cWallpaperCards; TextureCards { key: "theme.texture.wallpaper.kind" } }
    Component { id: cKeysStatus; KeysStatus {} }
    Component { id: cShortcut; ShortcutRecorder {} }

    contentWidth: width
    contentHeight: col.implicitHeight + Theme.pad * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function matches(row, q) {
        if (q === "") return true
        var hay = (row.key + " " + I18n.tr(row.label) + " " + (row.help ? I18n.tr(row.help) : "")).toLowerCase()
        return hay.indexOf(q) >= 0
    }
    // pages -> sections -> rows after page / search / advanced filtering; empty groups dropped.
    // Rows are {row, pageId, crumb}: the crumb is what a search hit shows above its row. On a page (not a search), the
    // rows that pick an appearance pack (K53: style, look, palette) leave their section and open the page as blocks of
    // their own, in the schema's order (W29, docs/ux/looks.md "Settings").
    readonly property var view: {
        var q = p.query.trim().toLowerCase()
        var out = []
        var pages = p.structure
        var tr = I18n.strings   // re-evaluate when strings arrive
        for (var i = 0; i < pages.length; i++) {
            if (q === "" && pages[i].id !== p.pageId) continue
            var secs = [], blocks = []
            // The rows a pack block takes in with it (its companions), when the page has that block.
            var taken = {}, rowsByKey = {}
            pages[i].sections.forEach(function (sc) { sc.rows.forEach(function (r) {
                rowsByKey[r.key] = r
                if (q === "" && Store.isPackRow(r)) (p.packCompanions[r.choices_from] || []).forEach(function (k) { taken[k] = true })
            }) })
            for (var j = 0; j < pages[i].sections.length; j++) {
                var s = pages[i].sections[j]
                var rows = s.rows.filter(function (r) {
                    return (p.showAdvanced || !r.advanced || q !== "") && matches(r, q)
                })
                if (q === "") {
                    rows.filter(function (r) { return Store.isPackRow(r) }).forEach(function (r) {
                        blocks.push({ row: r, pageId: pages[i].id, crumb: "",
                                      companions: (p.packCompanions[r.choices_from] || []).filter(function (k) {
                                          return rowsByKey[k] !== undefined }) })
                    })
                    rows = rows.filter(function (r) { return !Store.isPackRow(r) && !taken[r.key] })
                }
                if (rows.length) secs.push({ id: s.id, label: s.label, rows: rows.map(function (r) {
                    return { row: r, pageId: pages[i].id,
                             crumb: I18n.pageTitle(pages[i].id, pages[i].label) + " › " + I18n.tr(s.label) + " › " + I18n.tr(r.label) }
                }) })
            }
            if (secs.length || blocks.length) out.push({ id: pages[i].id, label: pages[i].label, sections: secs, blocks: blocks })
        }
        return out
    }
    // How many settings a search looked through (the empty-search line names its scope, UX brief "empty search").
    readonly property int scopeCount: Store.allRows().length

    // The first search hit as {pageId, row}, or null (Enter in the search field).
    // A row whose name has the query wins over one whose help only mentions it ("palette" lands on Palette, not on the
    // Style whose help names a palette; W29).
    function firstHit() {
        var v = view
        var q = p.query.trim().toLowerCase()
        var first = null
        for (var i = 0; i < v.length; i++)
            for (var j = 0; j < v[i].sections.length; j++)
                for (var k = 0; k < v[i].sections[j].rows.length; k++) {
                    var w = v[i].sections[j].rows[k]
                    if (I18n.tr(w.row.label).toLowerCase().indexOf(q) >= 0) return { pageId: w.pageId, row: w.row }
                    if (!first) first = { pageId: w.pageId, row: w.row }
                }
        return first
    }
    // After a jump the target page lays out on a later event: then the row is scrolled into view and
    // flashed once, and a keyboard jump moves the focus onto its control. Nothing repeats and no timer runs.
    // The row stays pinned at the top while the page settles (cards and previews that arrive later change the height
    // above it; a host that is still taking its size changes the layout); the user's hand on the page — a scroll, a
    // press, a key that moves the focus — or another jump lets it go. No timer: it follows layout changes only.
    property string pinKey: ""
    function placeRow(key) {
        var hit = findRow(col, key)
        if (!hit) return null
        var y = hit.mapToItem(p.contentItem, 0, 0).y
        // The first row of a card brings its card's title along (the section names what the row is part of).
        for (var c = hit.parent; c && c !== col; c = c.parent) {
            if (!c.objectName || (c.objectName.indexOf("section:") !== 0 && c.objectName.indexOf("block:") !== 0)) continue
            var top = c.mapToItem(p.contentItem, 0, 0).y
            if (y - top < 80) y = top
            break
        }
        p.contentY = Math.max(0, Math.min(y - Theme.pad, p.contentHeight - p.height))
        return hit
    }
    function reveal(key, focusIt) {
        p.pinKey = ""
        Qt.callLater(function () {
            var hit = p.placeRow(key)
            if (!hit) return
            hit.flash()
            if (focusIt) hit.focusControl()
            p.pinKey = key
        })
    }
    function replace() { if (pinKey !== "") Qt.callLater(function () { if (p.pinKey !== "") p.placeRow(p.pinKey) }) }
    onContentHeightChanged: replace()
    onWidthChanged: replace()
    onHeightChanged: replace()
    onMovementStarted: pinKey = ""
    onPageIdChanged: pinKey = ""
    onQueryChanged: pinKey = ""
    PointHandler {
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        onActiveChanged: if (active) p.pinKey = ""
    }
    Connections {
        target: p.Window.window
        enabled: p.pinKey !== ""
        function onActiveFocusItemChanged() { p.pinKey = "" }
    }
    function findRow(item, key) {
        if (item.row && item.row.key === key) return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var found = findRow(kids[i], key)
            if (found) return found
        }
        return null
    }
    // Opens the dropdown of a row on this page: the settings test hook (the keyboard opens it the same way).
    function openControl(key) {
        var hit = findRow(col, key)
        if (hit) hit.openControl()
    }
    // The settings test: the section cards on screen ("page.section"), and a theme export copy's result by app.
    function cardNames() {
        var out = []
        var walk = function (item) {
            if (item.objectName && item.objectName.indexOf("section:") === 0) { if (item.visible) out.push(item.objectName.substring(8)); return }
            if (item.objectName && item.objectName.indexOf("block:") === 0) { if (item.visible) out.push(item.objectName); return }
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) walk(kids[i])
        }
        walk(col)
        return out
    }
    function copyState(name) {
        var found = "none"
        var walk = function (item) {
            if (item.copied !== undefined && item.targets !== undefined) {
                var c = item.copied[name]
                found = c ? (c.error ? "error: " + c.error : "copied") : "none"
                return
            }
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) walk(kids[i])
        }
        walk(col)
        return found
    }
    // The keys test (K64): the shortcut recorder of a row — recording, a pending Replace, the lines under it — and the
    // copy result of the include line.
    function recorder(key) { return findNamed(col, "recorder:" + key) }
    function keysRow(key) {
        var r = recorder(key)
        if (!r) return "none"
        var lines = []
        var walk = function (item) {
            if (item.objectName === "keyline:" + key && item.visible) lines.push(item.children[0].text)
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) walk(kids[i])
        }
        walk(r)
        return JSON.stringify({ recording: r.recording, pending: r.pending ? r.pending.combo + ">" + r.pending.key : "",
                                notice: r.notice, inhibiting: r.inhibiting, lines: lines })
    }
    function keysCopied() { var s = findNamed(col, "keys-status"); return s ? s.copyState : "none" }
    // The settings test (W29): an item on the page by its objectName, or null.
    function findNamed(item, name) {
        if (item.objectName === name && item.visible) return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var f = findNamed(kids[i], name)
            if (f) return f
        }
        return null
    }
    // A row's value picked as its control would (a card's click): a style or a look by its action.
    function pick(key, value) {
        var hit = findRow(col, key)
        if (hit) hit.setValue(value)
    }
    // The category chips of a row's cards ("modern,inspired,…") and the open one, and a chip's click.
    function categories(key) { var c = findNamed(col, "cards:" + key); return c && c.categoryIds ? c.categoryIds() : "" }
    function openCategory(key) { var c = findNamed(col, "cards:" + key); return c && c.openCat !== undefined ? c.openCat : "" }
    function openCategoryOf(key, id) { var c = findNamed(col, "cards:" + key); if (c && c.open) c.open(id) }
    // The "differs from the style" line as shown ("" when hidden), and its Reset.
    function differs() { var d = findNamed(col, "differs"); return d ? d.text : "" }
    function resetToStyle() { var b = findNamed(col, "differs-reset"); if (b) b.press() }
    // The scroll position that brings an item named so into view (shots of a block).
    function scrollTo(name) {
        p.pinKey = ""
        var it = findNamed(col, name)
        if (!it) return
        var y = it.mapToItem(p.contentItem, 0, 0).y
        p.contentY = Math.max(0, Math.min(y - Theme.pad, p.contentHeight - p.height))
    }
    // A reason's link: the setting that controls this row, wherever it is.
    function openKey(key) {
        var h = Store.rowOf(key)
        if (h) p.jumpRequested(h.pageId, h.row, false)
    }
    // A page that is not in the schema any more (a mod removed from disk while its page was open): the page says so.
    readonly property bool pageMissing: !p.searching && p.pageId !== "" && p.structure.every(function (x) {
        return x.id !== p.pageId
    })

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: p.width - 2 * Theme.pad
        spacing: Theme.pad

        PageHeader {
            visible: !p.searching
            width: col.width
            text: p.heading
        }
        // A page's own reset: every setting the user set here, previewed as a diff and then made one change.
        ResetFlow {
            visible: !p.searching && p.userOps.length > 0
            ops: p.userOps
            enabled: Store.live
            tag: "page:" + p.pageId
            label: I18n.fmt("settings.ui.reset_page", { n: p.userOps.length })
        }
        ModHead {
            visible: !p.searching && p.modId !== ""
            modId: p.modId
            onPageRequested: id => p.pageRequested(id)
        }
        Text {
            visible: p.view.length === 0
            width: col.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            // A mod without settings has an empty page: its head, with the switch, says what there is. A search that
            // finds nothing names what it looked through.
            text: !Store.live ? I18n.tr("settings.ui.disconnected")
                : p.pageMissing ? I18n.tr("settings.ui.mod_gone")
                : p.searching ? I18n.fmt("settings.ui.no_match_scope", { query: p.query.trim(), count: p.scopeCount })
                : I18n.tr(p.modId !== "" ? "settings.mods.no_settings" : "settings.ui.no_results")
        }
        Repeater {
            model: p.view
            delegate: Column {
                required property var modelData
                width: col.width
                spacing: Theme.pad
                // The appearance packs' blocks (W29): Style, Look, Palette, each a card titled with the setting's name, its
                // control the whole width; the style's card adds the "differs from the style" line.
                Repeater {
                    model: modelData.blocks
                    delegate: SectionCard {
                        id: blk
                        required property var modelData
                        objectName: "block:" + modelData.row.key
                        width: col.width
                        title: I18n.tr(modelData.row.label)
                        icon: p.packIcons[modelData.row.choices_from] || "palette"
                        SettingRow {
                            width: blk.width - 2 * Theme.pad
                            rowKey: blk.modelData.row.key
                            output: p.output
                            stacked: true
                            divider: blk.modelData.companions.length > 0
                            onOpenKey: key => p.openKey(key)
                        }
                        Repeater {
                            model: blk.modelData.companions
                            delegate: Column {
                                required property var modelData
                                required property int index
                                readonly property var extra: p.pickers[modelData] ? undefined : p.extraOf(modelData)
                                width: blk.width - 2 * Theme.pad
                                SettingRow {
                                    width: parent.width
                                    rowKey: parent.modelData
                                    picker: p.pickerOf(parent.modelData)
                                    output: p.output
                                    divider: parent.index < blk.modelData.companions.length - 1 && parent.extra === undefined
                                    onOpenKey: key => p.openKey(key)
                                }
                                // A companion's document under it, as for a section's row (`extras`).
                                Loader {
                                    // Under the control column, as a section row's document is.
                                    x: Math.min(300, Math.max(180, parent.width * 0.36)) + Theme.pad
                                    width: parent.width - x
                                    active: parent.extra !== undefined
                                    sourceComponent: parent.extra ?? null
                                }
                            }
                        }
                        Loader {
                            width: blk.width - 2 * Theme.pad
                            active: blk.modelData.row.choices_from === "styles"
                            sourceComponent: StyleDiffers {}
                        }
                    }
                }
                Repeater {
                    model: modelData.sections
                    delegate: SectionCard {
                        id: sec
                        required property var modelData
                        readonly property string pageOf: modelData.rows.length ? modelData.rows[0].pageId : ""
                        objectName: "section:" + pageOf + "." + modelData.id
                        width: col.width
                        header: !p.searching
                        title: I18n.tr(modelData.label)
                        icon: p.sectionIcon(pageOf, modelData.id)
                        Repeater {
                            model: sec.modelData.rows
                            delegate: Column {
                                required property var modelData
                                required property int index
                                readonly property bool last: index === sec.modelData.rows.length - 1
                                readonly property var extra: p.pickers[modelData.row.key] ? undefined : p.extraOf(modelData.row.key)
                                width: sec.width - 2 * Theme.pad
                                spacing: 2
                                // The breadcrumb of a search hit: a link to the row, reachable by Tab.
                                Item {
                                    id: crumb
                                    visible: p.searching
                                    width: parent.width
                                    height: Theme.controlH
                                    activeFocusOnTab: true
                                    Keys.onReturnPressed: event => { p.jumpRequested(modelData.pageId, modelData.row, true); event.accepted = true }
                                    Keys.onEnterPressed: event => { p.jumpRequested(modelData.pageId, modelData.row, true); event.accepted = true }
                                    Keys.onSpacePressed: event => { p.jumpRequested(modelData.pageId, modelData.row, true); event.accepted = true }
                                    Accessible.role: Accessible.Link
                                    Accessible.name: modelData.crumb
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width
                                        elide: Text.ElideRight
                                        color: Theme.fg
                                        font.pixelSize: Theme.fs - 2
                                        font.family: Theme.fam(text, Theme.families)
                                        font.underline: hover.hovered || crumb.activeFocus
                                        text: modelData.crumb
                                    }
                                    HoverHandler { id: hover }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: p.jumpRequested(modelData.pageId, modelData.row, false)
                                    }
                                    FocusRing {
                                        anchors.fill: parent
                                        shown: crumb.activeFocus
                                        corner: Theme.rSm
                                    }
                                }
                                SettingRow {
                                    width: parent.width
                                    rowKey: modelData.row.key
                                    output: p.output
                                    divider: !parent.last && parent.extra === undefined
                                    picker: p.pickerOf(modelData.row.key)
                                    onOpenKey: key => p.openKey(key)
                                }
                                // A row's document beside it (the per-key map `extras`), under the control column.
                                Item {
                                    visible: parent.extra !== undefined
                                    width: parent.width
                                    height: visible ? extraLoader.height + Theme.gap * 2 : 0
                                    Loader {
                                        id: extraLoader
                                        readonly property real labelW: Math.min(300, Math.max(180, parent.width * 0.36))
                                        x: labelW + Theme.pad
                                        y: Theme.gap / 2
                                        width: parent.width - x
                                        active: parent.visible
                                        sourceComponent: parent.parent.extra ?? null
                                    }
                                    Rectangle {
                                        visible: !parent.parent.last
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 1
                                        color: Theme.containerHigh
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Related pages (UX brief, settings 7): links, not a menu. Hidden while searching.
        Row {
            visible: !p.searching && p.relatedPages.length > 0
            topPadding: Theme.pad
            spacing: Theme.gap
            Text {
                height: Theme.controlH - 8
                verticalAlignment: Text.AlignVCenter
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.ui.related") + ":"
            }
            Repeater {
                model: p.relatedPages
                delegate: LinkText {
                    required property var modelData
                    text: I18n.tr("settings.page." + modelData)
                    onActivated: p.pageRequested(modelData)
                }
            }
        }
    }
}
