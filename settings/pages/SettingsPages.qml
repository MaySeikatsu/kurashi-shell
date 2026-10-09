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
    // Rows are {row, pageId, crumb}: the crumb is what a search hit shows above its row.
    readonly property var view: {
        var q = p.query.trim().toLowerCase()
        var out = []
        var pages = p.structure
        var tr = I18n.strings   // re-evaluate when strings arrive
        for (var i = 0; i < pages.length; i++) {
            if (q === "" && pages[i].id !== p.pageId) continue
            var secs = []
            for (var j = 0; j < pages[i].sections.length; j++) {
                var s = pages[i].sections[j]
                var rows = s.rows.filter(function (r) {
                    return (p.showAdvanced || !r.advanced || q !== "") && matches(r, q)
                })
                if (rows.length) secs.push({ id: s.id, label: s.label, rows: rows.map(function (r) {
                    return { row: r, pageId: pages[i].id,
                             crumb: I18n.pageTitle(pages[i].id, pages[i].label) + " › " + I18n.tr(s.label) + " › " + I18n.tr(r.label) }
                }) })
            }
            if (secs.length) out.push({ id: pages[i].id, label: pages[i].label, sections: secs })
        }
        return out
    }
    // How many settings a search looked through (the empty-search line names its scope, UX brief "empty search").
    readonly property int scopeCount: Store.allRows().length

    // The first search hit as {pageId, row}, or null (Enter in the search field).
    function firstHit() {
        var v = view
        for (var i = 0; i < v.length; i++)
            for (var j = 0; j < v[i].sections.length; j++) {
                var w = v[i].sections[j].rows[0]
                if (w) return { pageId: w.pageId, row: w.row }
            }
        return null
    }
    // After a jump the target page lays out on a later event: then the row is scrolled into view and
    // flashed once, and a keyboard jump moves the focus onto its control. Nothing repeats and no timer runs.
    function reveal(key, focusIt) {
        Qt.callLater(function () {
            var hit = findRow(col, key)
            if (!hit) return
            var y = hit.mapToItem(p.contentItem, 0, 0).y
            p.contentY = Math.max(0, Math.min(y - Theme.pad, p.contentHeight - p.height))
            hit.flash()
            if (focusIt) hit.focusControl()
        })
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
                spacing: Theme.gap
                Repeater {
                    model: modelData.sections
                    delegate: Column {
                        required property var modelData
                        width: col.width
                        spacing: 0
                        Text {
                            visible: !p.searching
                            bottomPadding: Theme.gap
                            topPadding: Theme.gap
                            color: Theme.dim
                            font.pixelSize: Theme.fs
                            font.bold: true
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(modelData.label)
                        }
                        Repeater {
                            model: modelData.rows
                            delegate: Column {
                                required property var modelData
                                width: col.width
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
                                    onOpenKey: key => p.openKey(key)
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
