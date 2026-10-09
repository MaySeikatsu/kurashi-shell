import QtQuick
import "../core"
import "../components"

// Renders `schema.settings` rows for one page, or for every page matching a search query.
Flickable {
    id: p
    property string pageId: ""
    property string query: ""
    property bool showAdvanced: false
    property string output: ""

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
                if (rows.length) secs.push({ id: s.id, label: s.label, rows: rows })
            }
            if (secs.length) out.push({ id: pages[i].id, label: pages[i].label, sections: secs })
        }
        return out
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
                Text {
                    visible: p.query.trim() !== ""
                    color: Theme.accent
                    font.pixelSize: Theme.fsTitle
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(modelData.label)
                }
                Repeater {
                    model: modelData.sections
                    delegate: Column {
                        required property var modelData
                        width: col.width
                        spacing: 0
                        Text {
                            bottomPadding: Theme.gap
                            color: Theme.dim
                            font.pixelSize: Theme.fs
                            font.bold: true
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(modelData.label)
                        }
                        Repeater {
                            model: modelData.rows
                            delegate: SettingRow {
                                required property var modelData
                                width: col.width
                                row: modelData
                                output: p.output
                            }
                        }
                    }
                }
            }
        }
    }
}
