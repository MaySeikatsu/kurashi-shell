import QtQuick
import "../core"
import "../components"

// Renders `schema.settings` rows for one page, or for every page matching a search query. A search
// hit shows its breadcrumb (page › section › label); choosing one emits jumpRequested.
Flickable {
    id: p
    property string pageId: ""
    property string query: ""
    property bool showAdvanced: false
    property string output: ""
    signal jumpRequested(string targetPage, var row)

    readonly property bool searching: query.trim() !== ""

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
        var pages = Store.schema.pages || []
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
    // flashed once. Nothing repeats and no timer runs.
    function reveal(key) {
        Qt.callLater(function () {
            var hit = findRow(col, key)
            if (!hit) return
            var y = hit.mapToItem(p.contentItem, 0, 0).y
            p.contentY = Math.max(0, Math.min(y - Theme.pad, p.contentHeight - p.height))
            hit.flash()
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

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: p.width - 2 * Theme.pad
        spacing: Theme.pad

        Text {
            visible: p.view.length === 0
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr(Store.live ? "settings.ui.no_results" : "settings.ui.disconnected")
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
                                Text {
                                    visible: p.searching
                                    width: parent.width
                                    elide: Text.ElideRight
                                    color: crumbs.containsMouse ? Theme.fg : Theme.accent
                                    font.pixelSize: Theme.fs - 2
                                    font.family: Theme.fam(text, Theme.families)
                                    text: modelData.crumb
                                    MouseArea {
                                        id: crumbs
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: p.jumpRequested(modelData.pageId, modelData.row)
                                    }
                                }
                                SettingRow {
                                    width: parent.width
                                    row: modelData.row
                                    output: p.output
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
