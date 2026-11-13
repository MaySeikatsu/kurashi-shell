import QtQuick
import Quickshell
import "../core"
import "groups.js" as Grp   // the group edits Settings uses too (W80; settings/components links this file)
import "menus/rows.js" as Rows

// What a module's right-click menu lists (I408, docs/ux/module-menu.md): the settings the schema gives the module
// (`#[kurashi(module = "<id>")]`; a mod's whole page), as a tree TrayMenu draws, the same card and keys as a tray item's menu. A pure view of `schema.settings` and `config`: a toggle
// is a check mark, a choice or a range a submenu of radio rows; a row the daemon holds inert stays visible, greyed, with its
// reason under it (Shōjiki). Choosing a row sends an apply; the document's answer redraws the tree. Ma: the schema
// document is watched only while the menu is open.
Scope {
    id: mm
    // The module's id in its zone (`clock`, `mod:weather:bar`), "" while no menu is open.
    property string module: ""
    // BarConfig of the output the menu is on: the value in effect there, an output's own entry first.
    property var bars: null
    readonly property bool active: module !== ""
    readonly property string modId: module.indexOf("mod:") === 0 ? module.split(":")[1] : ""

    Watch { doc: "schema.settings"; active: mm.active }
    readonly property var schema: active ? Store.docs["schema.settings"] : null
    // The island's menu also says what is pinned (the document's face while `pinned`), and takes it back.
    readonly property bool isIsland: module === "island"
    Watch { doc: "runtime.island.main"; active: mm.isIsland }
    readonly property var island: isIsland ? Store.docs["runtime.island.main"] : null

    // The rows of this module, in the schema's order (menus/rows.js: the shared row rules of every right-click menu, W82).
    readonly property var rows: Rows.rowsWhere(schema, function (p, sec, r) {
        return (modId !== "" && p.mod === modId) || (r.modules || []).indexOf(mm.module) >= 0
    })
    readonly property string title: {
        if (!active) return ""
        var s = schema
        if (modId !== "" && s && s.pages)
            for (var i = 0; i < s.pages.length; i++)
                if (s.pages[i].mod === modId) return I18n.tr(s.pages[i].label)
        return modId !== "" ? modId : I18n.tr("layout.module." + module)
    }

    // A menu id for every row and choice, stable across redraws (TrayMenu keeps an open submenu by id).
    readonly property int settingsId: 999999
    function rowOf(key) { return Rows.rowOf(schema, key) }
    // A face's name, as the island's settings say it (a mod's face has its own).
    function faceLabel(id) {
        var r = rowOf("island.main.default"), cs = r && r.choices ? r.choices : []
        for (var i = 0; i < cs.length; i++) if (cs[i].value === id) return I18n.tr(cs[i].label)
        return I18n.tr("island.face." + id)
    }
    // The island's first rows: the face that is pinned, a check that takes the pin back, and a submenu to pin another.
    // (One at most: the island shows one face, K9.)
    function pinRows() {
        var d = island
        if (!d) return []
        var out = [], pinned = d.pinned === true ? d.face : "", faces = d.faces || []
        out.push({ id: 900000, label: I18n.tr(pinned !== "" ? "frontend.module.pinned" : "frontend.module.nothing_pinned"), enabled: false })
        if (pinned !== "")
            out.push({ id: 900001, label: faceLabel(pinned), toggle: "checkmark", checked: true,
                       act: { action: "island.pin", args: { face: pinned } } })
        var ch = []
        for (var i = 0; i < faces.length; i++)
            if (faces[i] !== pinned)
                ch.push({ id: 900010 + i, label: faceLabel(faces[i]), act: { action: "island.pin", args: { face: faces[i] } } })
        if (ch.length > 0) out.push({ id: 900002, label: I18n.tr("frontend.module.pin_face"), children: ch })
        out.push({ id: 900003, separator: true })
        return out
    }
    // Groups (I502, W80; docs/ux/groups.md "Round two"): the zone list this module stands in (its own entry, or a group's
    // members there), on this output: {key, list, groups, group, output} or null.
    readonly property var zone: {
        if (!active || !bars) return null
        var groups = bars.valueOf("layout.groups", [])
        if (!Array.isArray(groups)) groups = []
        var edges = ["top", "bottom", "left", "right"], zones = ["start", "center", "end"]
        for (var e = 0; e < edges.length; e++)
            for (var z = 0; z < zones.length; z++) {
                var key = "edges." + edges[e] + "." + zones[z], list = bars.valueOf(key, [])
                if (!Array.isArray(list)) continue
                var g = list.indexOf(module) >= 0 ? "" : Grp.groupOf(list, groups, module)
                if (list.indexOf(module) < 0 && g === "") continue
                var c = bars.config, out = bars.outName
                var own = out !== "" && c && c.outputs && c.outputs[out] && c.outputs[out][key] !== undefined
                return { key: key, list: list, groups: groups, group: g, output: own ? out : "" }
            }
        return null
    }
    function groupName(groups, id) {
        var r = Grp.recordOf(groups, id)
        return r && r.name ? r.name : id
    }
    // "Group with…" (the zone's other modules and groups) and "Leave group": each one apply of the records and the list.
    function groupRows() {
        var zn = zone
        if (!zn) return []
        var out = [], ch = []
        for (var i = 0; i < zn.list.length; i++) {
            var v = zn.list[i]
            if (v === module || (zn.group !== "" && v === Grp.entryOf(zn.group))) continue
            var res = Grp.dropOnto(zn.list, zn.groups, module, v)
            if (!res) continue
            var label = Grp.isGroup(v) ? I18n.tr("frontend.module.group_named").replace("{name}", groupName(zn.groups, Grp.idOf(v)))
                                     : I18n.tr("layout.module." + v)
            ch.push({ id: 960010 + i, label: label, act: { ops: Grp.ops(res, zn.key, zn.output) } })
        }
        if (ch.length > 0) out.push({ id: 960000, label: I18n.tr("frontend.module.group_with"), children: ch })
        if (zn.group !== "") {
            var lv = Grp.leave(zn.list, zn.groups, module)
            if (lv) out.push({ id: 960001, label: I18n.tr("frontend.module.leave_group").replace("{name}", groupName(zn.groups, zn.group)),
                               act: { ops: Grp.ops(lv, zn.key, zn.output) } })
        }
        return out
    }
    // Each entry carries what it does (`act`: `{key, value}` to set, `{action, args}` to send, or `{open: true}` for
    // Settings); TrayMenu ignores it.
    readonly property var tree: {
        var kids = isIsland ? pinRows() : []
        var list = rows
        kids = kids.concat(Rows.entries(schema, list, bars, 1, I18n.tr))
        if (list.length === 0 && schema) kids.push({ id: 999998, label: I18n.tr("frontend.module.none"), enabled: false })
        // I458: what a hover on this module opens: as the bar (`bar.hover`), or its own (`bar.hover_preview|card|menu`).
        if (bars) {
            var own = Peeks.hoverOwn(module), modes = ["", "preview", "card", "menu"], hk = []
            for (var hi = 0; hi < modes.length; hi++)
                hk.push({ id: 950001 + hi, label: I18n.tr("frontend.module.hover." + (modes[hi] || "bar")), toggle: "radio",
                          checked: own === modes[hi], act: { ops: hoverOps(modes[hi]) } })
            if (kids.length > 0) kids.push({ id: 950000, separator: true })
            kids.push({ id: 950010, label: I18n.tr("frontend.module.hover") + ": "
                + I18n.tr("frontend.module.hover." + (own || "bar")), children: hk })
        }
        var gr = groupRows()
        if (gr.length > 0) {
            if (kids.length > 0) kids.push({ id: 960099, separator: true })
            kids = kids.concat(gr)
        }
        if (kids.length > 0) kids.push({ id: 999997, separator: true })
        kids.push({ id: settingsId, label: I18n.tr("frontend.module.settings"),
                    act: { open: modId !== "" ? { page: "mod:" + modId } : list.length > 0 ? { key: list[0].key } : { page: "layout" } } })
        return { children: kids }
    }
    // The module out of every `bar.hover_*` list, then into the one chosen ("" follows the bar): one transaction.
    function hoverOps(mode) {
        var ops = [], l = Peeks.hoverLists, m = module
        for (var k in l) {
            var has = l[k].indexOf(m) >= 0
            if (k === mode && !has) ops.push({ set: "bar.hover_" + k, value: l[k].concat([m]) })
            else if (k !== mode && has) ops.push({ set: "bar.hover_" + k, value: l[k].filter(function (x) { return x !== m }) })
        }
        return ops
    }
    // Chooses a row; returns true when the menu is done (Settings opened), false when it stays for the next change.
    function choose(id) { return Rows.run(Store, bars, Rows.find(id, tree.children)) }
}
