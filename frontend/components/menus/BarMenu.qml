import QtQuick
import Quickshell
import "../../core"
import "rows.js" as Rows

// A bar's right-click menu, on an empty part of it (W82, docs/ux/context-menus.md "Rows per place"): the edge's own rows
// (`edges.<edge>.*`) and the bars' (`bar.*`) as the schema gives them — rule 3: the schema's own namespaces, no list of
// keys here; the module lists stay in Settings — each `per_output` row on this output's entry where it has one, and
// "Edit layout…". A pure view, as ModuleMenu. Ma: the schema is watched only while the menu is open.
Scope {
    id: bm
    // `bar:<output>/<edge>` while this menu is open, else "".
    property string target: ""
    property var bars: null
    readonly property bool active: target.indexOf("bar:") === 0
    readonly property string edge: {
        var s = target.substring(4), i = s.lastIndexOf("/")
        var e = i >= 0 ? s.substring(i + 1) : s
        return ["top", "bottom", "left", "right"].indexOf(e) >= 0 ? e : (bars ? bars.edge : "top")
    }

    Watch { doc: "schema.settings"; active: bm.active }
    readonly property var schema: active ? Store.docs["schema.settings"] : null
    readonly property var rows: Rows.rowsWhere(schema, function (p, s, r) { return r.key.indexOf("edges." + bm.edge + ".") === 0 }, false)
        .concat(Rows.rowsWhere(schema, function (p, s, r) { return r.key.indexOf("bar.") === 0 }, false))
    readonly property string title: I18n.tr("menus.bar." + edge)

    readonly property var tree: {
        var kids = schema ? Rows.entries(schema, rows, bars, 1, I18n.tr) : []
        if (kids.length > 0) kids.push({ id: 810001, separator: true })
        kids.push({ id: 810002, label: I18n.tr("menus.bar.edit_layout"), act: { open: { page: "layout" } } })
        return { children: kids }
    }
    function choose(id) { return Rows.run(Store, bars, Rows.find(id, tree.children)) }
}
