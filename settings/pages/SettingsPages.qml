import QtQuick
import QtQuick.Controls.Basic as QQC
import "../core"
import "../components"
import "../components/motion"

// Renders `schema.settings` rows for one page, or for every page matching a search query. A search hit shows its
// breadcrumb (page › section › label); choosing one emits jumpRequested, and so does a reason's link to the setting
// that controls a row. A page can reset the settings the user set on it (diff first), name its related pages (UX brief,
// settings 2 and 7), and a mod's page starts with its head (settings 5).
Flickable {
    id: p
    // Kinetic wheel and a grabbable scrollbar (session 17, docs/ux/settings.md).
    KineticWheel { view: p }
    QQC.ScrollBar.vertical: PageScrollBar {}
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

    // Settings › Layout: the edge whose section shows under the screen (K71; LayoutScreen picks it, the page keeps it).
    property string layoutEdge: "top"
    // Related pages (UX brief, settings 7): the pages whose settings act on this one's, when they exist.
    readonly property var relatedPages: {
        var m = { island: ["notifications"], notifications: ["island"], appearance: ["accessibility", "motion", "fonts"], fonts: ["appearance", "accessibility"],
                  accessibility: ["appearance", "motion"], layout: ["dock", "sidebar"], dock: ["layout"], sidebar: ["layout"],
                  motion: ["appearance", "accessibility"] }
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
        pen: "ink_pen", settings_app: "web_asset", shortcuts: "keyboard",
        "motion.profiles": "animation", "motion.timing": "speed", "motion.animation_style": "category",
        "motion.advanced_curves": "tune", "motion.choreography": "stack",
        "motion.windows": "web_asset", typography: "text_fields", font_mix: "draw"
    })
    function sectionIcon(pageId, id) {
        return sectionIcons[pageId + "." + id] || sectionIcons[id] || (pageId.indexOf("mods.") === 0 ? "extension" : "tune")
    }
    // A document a row shows beside it (the one place Settings does): row key -> component. The theme export says where
    // each app's file went and what the app still needs (K49).
    readonly property var extras: ({ "theme.export": cThemeExport, "theme.colors.scheme": cSchemeStatus,
                                       "theme.colors.season": cSeasonStatus,
                                       "sidebar.from_bar": cSidebarOpen, "theme.texture.kind": cTextureCards,
                                       "theme.light.mode": cLightDial, "theme.colors.ink": cInkSwatches,
                                       "theme.light.color": cLightSwatches, "theme.material.shadow": cShadowPreview,
                                       "theme.material.elevation": cElevationPreview,
                                       "theme.texture.wallpaper.kind": cWallpaperCards, "keys.write": cKeysStatus,
                                       "layout.draw": cDrawModes, "theme.frame_outline": cFrameOutline })
    // Extras that are the row's own picker (every offer, keyboard as a radio group): they take the place of the row's
    // dropdown (SettingRow.picker), with the provenance line under them.
    readonly property var pickers: ({ "theme.texture.kind": true, "theme.colors.ink": true, "theme.light.color": true,
                                      "theme.texture.wallpaper.kind": true, "layout.draw": true, "theme.frame_outline": true })
    // A document shown only while a switch is on (key -> the bool key): the wallpaper's own material cards (K61) show
    // while "Own material for the wallpaper" is on, and leave the row as a plain dropdown otherwise.
    readonly property var extraWhen: ({ "theme.texture.wallpaper.kind": "theme.texture.wallpaper.own" })
    // The picker that stands in for a row's control, or null (the generic control). A row whose schema control is
    // "shortcut" (K64: each `keys.*` shortcut) is recorded by keys, not typed; the schema says which rows those are.
    function pickerOf(key) {
        var r = Store.rowOf(key)
        if (r && r.row.control === "shortcut") return cShortcut
        // K83 (W59.6): a curve row is the curve editor; the motion profile its gallery; a form row the form picker.
        if (r && r.row.control === "curve") return cCurve
        if (key === "theme.motion.profile") return cProfiles
        if (r && r.row.choices_from === "motion.forms") return cFormPicker
        // A number whose lowest value means "the profile's" (-1 or 0): "From the profile (…)", never the raw sentinel.
        if (/^theme\.motion\.(jelly|squash|stagger_ms|timing\.[a-z]+_ms)$/.test(key)) return cProfileValue
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
    Component { id: cSeasonStatus; SeasonStatus {} }
    Component { id: cSidebarOpen; SidebarOpen {} }
    Component { id: cTextureCards; TextureCards {} }
    Component { id: cLightDial; LightDial {} }
    Component { id: cInkSwatches; InkSwatches {} }
    Component { id: cLightSwatches; LightSwatches {} }
    Component { id: cShadowPreview; ShadowPreview {} }
    Component { id: cFrameOutline; FrameOutlineCards {} }
    Component { id: cElevationPreview; ElevationPreview {} }
    Component { id: cWallpaperCards; TextureCards { key: "theme.texture.wallpaper.kind" } }
    Component { id: cKeysStatus; KeysStatus {} }
    Component { id: cShortcut; ShortcutRecorder {} }
    Component { id: cDrawModes; DrawModes {} }
    Component { id: cCurve; CurveControl {} }
    Component { id: cProfiles; ProfileGallery {} }
    Component { id: cFormPicker; FormPicker {} }
    Component { id: cProfileValue; ProfileValue {} }
    Component { id: cFormsTable; FormsTable { onOpenKey: key => p.openKey(key) } }
    // The note under the selected edge's header when its bar has no modules (Settings › Layout; EmptyBarNote).
    Component {
        id: cEmptyBar
        EmptyBarNote {
            edge: p.layoutEdge
            output: p.output
        }
    }
    // The screen of Settings › Layout (its own Loader: the layout document is watched only while it is shown, Ma).
    Component {
        id: cLayoutScreen
        LayoutScreen {
            width: parent.width
            output: p.output
            edge: p.layoutEdge
            onEdgePicked: e => p.layoutEdge = e
        }
    }

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
            var sections = q === "" && pages[i].id === "layout" ? p.layoutSections(pages[i].sections)
                : q === "" && pages[i].id === "motion" ? p.motionSections(pages[i].sections) : pages[i].sections
            for (var j = 0; j < sections.length; j++) {
                var s = sections[j]
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
    // Settings › Layout shows one edge at a time (K71): the selected edge's section comes first, under the screen, and the
    // other edges' sections are left out. The rest keep the schema's order. Not a filter on values: the list changes only
    // with the selected edge, so a value change does not rebuild the rows.
    function layoutSections(list) {
        const want = p.layoutEdge + "_edge"
        const first = list.filter(function (s) { return s.id === want })
        return first.concat(list.filter(function (s) { return s.id !== want && !/_edge$/.test(s.id) }))
    }
    // Settings › Motion (W59.6, brief docs/ux/motion-engine.md §8): the forms section keeps its two defaults as rows; the
    // per-surface forms and the island's switch are one table under them (FormsTable), so they leave the section's rows. A
    // search shows them as rows, as any other.
    function motionSections(list) {
        return list.map(function (s) {
            // S21: the speed lives in the preview stage (where it is tried), not under the profiles.
            if (s.id === "profiles") return { id: s.id, label: s.label, rows: s.rows.filter(function (r) {
                return r.key !== "theme.motion.speed" }) }
            if (s.id !== "animation_style") return s
            return { id: s.id, label: s.label, rows: s.rows.filter(function (r) {
                return r.key === "theme.motion.form.open" || r.key === "theme.motion.form.close" }) }
        })
    }
    // The settings test (W44): whether an item named so is on the page.
    function present(name) { return findNamed(col, name) !== null }
    // Settings › Motion's preview stage (the settings test drives it: shell.qml `preview`), or null off that page.
    function motionPreview() { return findNamed(col, "motion-preview") }
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
        p.contentY = Math.max(0, Math.min(y - Theme.pad - p.stickOver(y), p.contentHeight - p.height))
        return hit
    }
    // Settings › Motion's sticky preview stage (W59.6b): how far it is moved down to stay at the page's top, its height,
    // and the room a row below it needs so a jump does not land under it.
    readonly property real stuck: motionTop.active ? Math.max(0, p.contentY - col.y - motionTop.y) : 0
    readonly property real stuckH: motionTop.active && motionTop.item ? motionTop.item.children[0].height : 0
    function stickOver(y) { return p.stuckH > 0 && y > col.y + motionTop.y + p.stuckH ? p.stuckH + Theme.gap : 0 }
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
        p.contentY = Math.max(0, Math.min(y - Theme.pad - p.stickOver(y), p.contentHeight - p.height))
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

    // Session 26: the page's header stays at the top once it has scrolled away — the page's name and the section in view —
    // so rows do not run out into nothing at the top edge. An outlined strip on the ground (the pen, the wash and the
    // relief as every box of Settings), above the rows.
    readonly property real stickyH: 38
    readonly property bool stickyOn: !p.searching && p.contentY > col.y + pageHead.y + pageHead.height
    property string stickySection: ""
    function findSection() {
        if (!stickyOn) return
        var y = p.contentY - col.y + stickyH + Theme.gap
        var d = col.childAt(Theme.pad, y)
        var t = ""
        if (d) {
            var inner = d.childAt(Theme.pad, y - d.y)
            if (inner && inner.title !== undefined) t = inner.title
            else if (d.title !== undefined) t = d.title
        }
        if (t !== stickySection) stickySection = t
    }
    onContentYChanged: { findSection(); spy() }
    onStickyOnChanged: findSection()

    // ---- I464 (docs/ux/settings-sections.md): a page's sections, for the sidebar ----
    // `solo`: the one section shown ("" = the whole page): a click on a section in the sidebar shows that section alone,
    // a click on its page shows all of it again. `sectionId`: the section in view, for the sidebar's mark.
    property string solo: ""
    property string sectionId: ""
    // The cards of the page in order, as {id, item}: the sections that have rows to show now.
    function sectionCards() {
        var out = []
        var walk = function (item) {
            var n = item.objectName || ""
            // (a pack's block — Style, Look, Palette — is a section of the sidebar too, by its key)
            if (n.indexOf("block:") === 0) { out.push({ id: n, item: item }); return }
            if (n.indexOf("section:") === 0) { out.push({ id: n.substring(n.indexOf(".") + 1), item: item }); return }
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) walk(kids[i])
        }
        walk(col)
        return out
    }
    // The section whose card holds the line just under the header; the first one at the page's top.
    function spy() {
        if (p.searching) { if (sectionId !== "") sectionId = ""; return }
        if (solo !== "") { if (sectionId !== solo) sectionId = solo; return }
        var cards = sectionCards(), y = p.contentY + stickyH + 2 * Theme.gap, hit = cards.length ? cards[0].id : ""
        for (var i = 0; i < cards.length; i++) {
            if (!cards[i].item.visible) continue
            var top = cards[i].item.mapToItem(p.contentItem, 0, 0).y
            if (top <= y) hit = cards[i].id
        }
        if (hit !== sectionId) sectionId = hit
    }
    // What the sidebar lists under the open page: {id, title} of every card, in the page's order. Refreshed when the
    // page's cards are made (never per frame): the cards are the truth of what the page shows.
    property var navSections: []
    function refreshNav() {
        var cards = p.searching ? [] : sectionCards(), out = []
        for (var i = 0; i < cards.length; i++) out.push({ id: cards[i].id, title: String(cards[i].item.title || "") })
        navSections = out
        spy()
    }
    // (its own objects: the view already has handlers of these names)
    Connections { target: p; function onViewChanged() { Qt.callLater(p.refreshNav) } }
    Timer { interval: 0; running: true; onTriggered: p.refreshNav() }
    // I479 (scroll resistance; the user: "showing just the setting when clicked, but when scrolled a bit more it pops
    // out"): while one section is shown alone, scrolling on past its end (or back past its start) for a few notches opens
    // the whole page again at that section, on the side the scrolling came from. `push`: how far along (px of wheel);
    // it relaxes after a pause, so a single stray notch does nothing.
    readonly property real pushOutAt: 420
    property real push: 0
    property int pushDir: 0
    WheelHandler {
        enabled: p.solo !== "" && !p.searching
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            // (a touchpad scrolls in phases, in px; a wheel in notches of 120, and since Qt 6.12 reports a pixelDelta too:
            // KineticWheel, B42. A notch counts as 140 px: three notches open the page)
            var dy = event.phase !== Qt.NoScrollPhase ? event.pixelDelta.y : event.angleDelta.y / 120 * 140
            if (dy === 0) return
            var down = dy < 0
            // (the view's own word for its ends: it knows its margins and origin)
            var atEnd = p.atYEnd, atTop = p.atYBeginning
            if ((down && atEnd) || (!down && atTop)) {
                var dir = down ? 1 : -1
                if (dir !== p.pushDir) { p.pushDir = dir; p.push = 0 }
                p.push += Math.abs(dy)
                relax.restart()
                if (p.push >= p.pushOutAt) p.popOut(dir)
            } else if (p.push !== 0) {
                p.push = 0
            }
        }
    }
    // (long enough to go on after a breath, short enough that a notch from a minute ago does not count)
    Timer { id: relax; interval: 1800; onTriggered: p.push = 0 }
    function popOut(dir) {
        var id = solo
        push = 0
        solo = ""
        Qt.callLater(function () { p.toSection(id, dir) })
    }
    // Brings section `id` of the whole page into view: its top under the header, or (dir > 0, coming from its end) its
    // end at the view's bottom, so the scrolling goes on where it was.
    function toSection(id, dir) {
        var cards = sectionCards()
        for (var i = 0; i < cards.length; i++) {
            if (cards[i].id !== id) continue
            var top = cards[i].item.mapToItem(p.contentItem, 0, 0).y
            var y = dir > 0 ? top + cards[i].item.height - p.height + Theme.gap : top - stickyH - Theme.gap
            p.contentY = Math.max(0, Math.min(Math.max(0, p.contentHeight - p.height), y))
            break
        }
        spy()
    }
    // Shows `id` alone and brings it to the top; "" shows the whole page from its top.
    function showSection(id) {
        solo = id
        pinKey = ""
        contentY = 0
        Qt.callLater(spy)
    }
    // I479: the resistance, shown: while the scrolling pushes against a section's end, a pill at that end says what going
    // on will do and how far along it is (so the page never opens by surprise).
    Rectangle {
        objectName: "sectionPush"
        z: 11
        visible: p.push > 0 && p.solo !== ""
        readonly property real t: Math.min(1, p.push / p.pushOutAt)
        width: Math.min(p.width - 2 * Theme.pad, pushText.implicitWidth + 2 * Theme.pad)
        height: Theme.controlH
        x: (p.width - width) / 2
        y: p.pushDir > 0 ? p.contentY + p.height - height - Theme.gap : p.contentY + p.stickyH + 2 * Theme.gap
        radius: height / 2
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.outline
        clip: true
        Rectangle { width: parent.width * parent.t; height: parent.height; color: Theme.selected }
        Text {
            id: pushText
            anchors.centerIn: parent
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            color: Theme.fg
            font.pixelSize: Theme.fs - 1
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.section_push")
        }
    }
    Item {
        id: sticky
        z: 10
        visible: p.stickyOn
        x: Theme.pad
        y: p.contentY
        width: p.width - 2 * Theme.pad
        height: p.stickyH + Theme.gap
        // The ground behind the strip, so rows pass under it instead of showing through the gap above it.
        Rectangle { anchors.fill: parent; anchors.leftMargin: -Theme.pad; anchors.rightMargin: -Theme.pad; color: Theme.surface }
        Loader {
            anchors.fill: parent
            anchors.leftMargin: -Theme.pad
            anchors.rightMargin: -Theme.pad
            active: Theme.washOn && sticky.visible
            sourceComponent: Wash { fill: Theme.surface }
        }
        RoundBox {
            id: stickyFace
            y: Theme.gap / 2
            width: parent.width
            height: p.stickyH
            radius: Theme.rSm
            color: Theme.surface
            border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
            border.color: Theme.outlineW > 0 ? Theme.line : Theme.outline
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.pad
                width: parent.width - 2 * Theme.pad
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.fam(text, Theme.families)
                font.pixelSize: Theme.fs + 1
                font.weight: Theme.wBold
                text: p.heading + (p.stickySection !== "" ? "  ·  " + p.stickySection : "")
            }
        }
    }

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: p.width - 2 * Theme.pad
        spacing: Theme.pad

        PageHeader {
            id: pageHead
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
        // Settings › Fonts: the comparison of the mix on top (K93). Only on that page.
        Loader {
            width: col.width
            active: !p.searching && p.pageId === "fonts"
            visible: active
            sourceComponent: FontMixPreview {}
        }
        // Settings › Motion: the preview stage on top and the reduce-motion line under it (W59.6). Only on that page. The
        // stage is sticky (brief §8 item 1): scrolled past, it stays at the page's top over the rows (W59.6b).
        Loader {
            id: motionTop
            width: col.width
            z: 2
            active: !p.searching && p.pageId === "motion"
            visible: active
            sourceComponent: Column {
                spacing: Theme.gap
                MotionPreview {
                    width: parent.width
                    onOpenKey: key => p.openKey(key)
                    transform: Translate { y: p.stuck }
                }
                MotionA11y { onOpenKey: key => p.openKey(key) }
            }
        }
        // Settings › Layout: the screen with the edges, above the selected edge's section (LayoutScreen). Only on that page.
        Loader {
            width: col.width
            active: !p.searching && p.pageId === "layout"
            visible: active
            sourceComponent: cLayoutScreen
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
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
                        // I464: a section chosen in the sidebar is shown alone.
                        visible: p.searching || p.solo === "" || p.solo === objectName
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
                        // W53.0b (K80): the style's layout preset, offered, never applied by itself.
                        Loader {
                            width: blk.width - 2 * Theme.pad
                            active: blk.modelData.row.choices_from === "styles"
                            sourceComponent: LayoutOffer {}
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
                        // I464: a section chosen in the sidebar is shown alone.
                        visible: p.searching || p.solo === "" || modelData.id === p.solo
                        // Settings › Layout: the selected edge's bar with no modules says so, under the section's header (UX brief,
                        // docs/ux/layout.md "States"). Only that section, and only on the page.
                        Loader {
                            width: sec.width - 2 * Theme.pad
                            active: pageOf === "layout" && !p.searching && modelData.id === p.layoutEdge + "_edge"
                            visible: active
                            sourceComponent: cEmptyBar
                        }
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
                                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                        antialiasing: !Theme.pixelType
                                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
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
                        // Settings › Motion: the forms per surface, as one table under the two defaults (motionSections).
                        Loader {
                            width: sec.width - 2 * Theme.pad
                            active: pageOf === "motion" && !p.searching && sec.modelData.id === "animation_style"
                            visible: active
                            sourceComponent: cFormsTable
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
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
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
