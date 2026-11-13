import QtQuick
import Quickshell
import "../core"
// The one set of group edits (W80): Settings' list and this menu write the same ops.
import "../../settings/components/groups.js" as G

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

    // The rows of this module, in the schema's order.
    readonly property var rows: {
        var out = [], s = schema
        if (!s || !s.pages) return out
        for (var i = 0; i < s.pages.length; i++) {
            var p = s.pages[i]
            var whole = modId !== "" && p.mod === modId
            for (var j = 0; j < p.sections.length; j++) {
                var rs = p.sections[j].rows
                for (var k = 0; k < rs.length; k++)
                    if ((whole || (rs[k].modules || []).indexOf(module) >= 0) && drawable(rs[k])) out.push(rs[k])
            }
        }
        return out
    }
    readonly property string title: {
        if (!active) return ""
        var s = schema
        if (modId !== "" && s && s.pages)
            for (var i = 0; i < s.pages.length; i++)
                if (s.pages[i].mod === modId) return I18n.tr(s.pages[i].label)
        return modId !== "" ? modId : I18n.tr("layout.module." + module)
    }
    function drawable(r) {
        if (r.advanced === true) return false
        return r.control === "toggle" || r.control === "slider" || ((r.control === "select" || r.control === "pick_list") && !!r.choices)
    }

    // A menu id for every row and choice, stable across redraws (TrayMenu keeps an open submenu by id).
    readonly property int settingsId: 999999
    function idOf(rowIndex, choice) { return 1 + rowIndex * 100 + choice }
    function stepsOf(r, now) {
        var n = Math.round((r.max - r.min) / r.step)
        var out = []
        if (n <= 8) { for (var i = 0; i <= n; i++) out.push(r.min + i * r.step) }
        else {
            for (var j = 0; j <= 4; j++) out.push(r.min + Math.round(j * n / 4) * r.step)
            if (out.indexOf(now) < 0) { out.push(now); out.sort(function (a, b) { return a - b }) }
        }
        return out
    }
    function withUnit(r, v) { return String(v) + (r.unit ? " " + r.unit : "") }
    // Why a row does nothing now. A setting another one holds names it, with the value it needs where one does.
    function inertWhy(r, p) {
        if (!p) return ""
        if (!p.forced_by && p.reason !== "settings.inert.requires") return ""
        var by = p.inert_by && rowOf(p.inert_by)
        if (!by) return I18n.tr("frontend.module.held")
        var text = I18n.tr(by.label), cs = r.couplings || []
        for (var i = 0; i < cs.length; i++) {
            if (cs[i].key !== p.inert_by || cs[i].kind !== "requires" || cs[i].op !== "eq") continue
            var ch = by.choices || []
            for (var j = 0; j < ch.length; j++) if (ch[j].value === cs[i].value) text += ": " + I18n.tr(ch[j].label)
        }
        return I18n.tr("frontend.module.needs").replace("{key}", text)
    }
    function rowOf(key) {
        var s = schema
        for (var i = 0; s && i < s.pages.length; i++)
            for (var j = 0; j < s.pages[i].sections.length; j++) {
                var rs = s.pages[i].sections[j].rows
                for (var k = 0; k < rs.length; k++) if (rs[k].key === key) return rs[k]
            }
        return null
    }
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
                var g = list.indexOf(module) >= 0 ? "" : G.groupOf(list, groups, module)
                if (list.indexOf(module) < 0 && g === "") continue
                var c = bars.config, out = bars.outName
                var own = out !== "" && c && c.outputs && c.outputs[out] && c.outputs[out][key] !== undefined
                return { key: key, list: list, groups: groups, group: g, output: own ? out : "" }
            }
        return null
    }
    function groupName(groups, id) {
        var r = G.recordOf(groups, id)
        return r && r.name ? r.name : id
    }
    // "Group with…" (the zone's other modules and groups) and "Leave group": each one apply of the records and the list.
    function groupRows() {
        var zn = zone
        if (!zn) return []
        var out = [], ch = []
        for (var i = 0; i < zn.list.length; i++) {
            var v = zn.list[i]
            if (v === module || (zn.group !== "" && v === G.entryOf(zn.group))) continue
            var res = G.dropOnto(zn.list, zn.groups, module, v)
            if (!res) continue
            var label = G.isGroup(v) ? I18n.tr("frontend.module.group_named").replace("{name}", groupName(zn.groups, G.idOf(v)))
                                     : I18n.tr("layout.module." + v)
            ch.push({ id: 960010 + i, label: label, act: { ops: G.ops(res, zn.key, zn.output) } })
        }
        if (ch.length > 0) out.push({ id: 960000, label: I18n.tr("frontend.module.group_with"), children: ch })
        if (zn.group !== "") {
            var lv = G.leave(zn.list, zn.groups, module)
            if (lv) out.push({ id: 960001, label: I18n.tr("frontend.module.leave_group").replace("{name}", groupName(zn.groups, zn.group)),
                               act: { ops: G.ops(lv, zn.key, zn.output) } })
        }
        return out
    }
    // Each entry carries what it does (`act`: `{key, value}` to set, `{action, args}` to send, or `{open: true}` for
    // Settings); TrayMenu ignores it.
    readonly property var tree: {
        var kids = isIsland ? pinRows() : []
        var list = rows
        for (var i = 0; i < list.length; i++) {
            var r = list[i], p = bars ? bars.entry(r.key) : null
            var now = p && p.value !== undefined ? p.value : r.default
            var why = inertWhy(r, p)
            var live = why === ""
            var id = idOf(i, 0)
            if (r.control === "toggle") {
                kids.push({ id: id, label: I18n.tr(r.label), toggle: "checkmark", checked: now === true, enabled: live,
                            act: { key: r.key, value: now !== true } })
            } else if (r.control === "pick_list") {
                // A list to pick from: each choice a check mark, the list in its order with a new one at its end.
                var picked = Array.isArray(now) ? now : []
                var pk = []
                for (var pi = 0; pi < r.choices.length; pi++) {
                    var v = r.choices[pi].value, on = picked.indexOf(v) >= 0
                    pk.push({ id: idOf(i, pi + 1), label: I18n.tr(r.choices[pi].label), toggle: "checkmark", checked: on, enabled: live,
                              act: { key: r.key, value: on ? picked.filter(function (x) { return x !== v }) : picked.concat([v]) } })
                }
                kids.push({ id: id, label: I18n.tr(r.label), enabled: live, children: pk })
            } else {
                var opts = r.control === "slider"
                    ? stepsOf(r, now).map(function (v) { return { value: v, label: mm.withUnit(r, v) } })
                    : r.choices.map(function (c) { return { value: c.value, label: I18n.tr(c.label) } })
                var shown = String(now)
                var ch = []
                for (var j = 0; j < opts.length; j++) {
                    var cid = idOf(i, j + 1)
                    if (opts[j].value === now) shown = opts[j].label
                    ch.push({ id: cid, label: opts[j].label, toggle: "radio", checked: opts[j].value === now, enabled: live,
                              act: { key: r.key, value: opts[j].value } })
                }
                kids.push({ id: id, label: I18n.tr(r.label) + ": " + shown, enabled: live, children: ch })
            }
            // (once for a run of rows held for the one reason)
            var nextP = i + 1 < list.length && bars ? bars.entry(list[i + 1].key) : null
            if (!live && inertWhy(list[i + 1] || {}, nextP) !== why) kids.push({ id: id + 50, label: why, enabled: false })
        }
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
        kids.push({ id: settingsId, label: I18n.tr("frontend.module.settings"), act: { open: true } })
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
    function find(id, list) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].id === id) return list[i].act || null
            var hit = list[i].children ? find(id, list[i].children) : null
            if (hit) return hit
        }
        return null
    }
    function choose(id) {
        var a = find(id, tree.children)
        if (!a) return false
        if (a.open) {
            var list = rows
            if (modId !== "") Store.act("settings.open", { page: "mod:" + modId })
            else if (list.length > 0) Store.act("settings.open", { key: list[0].key })
            else Store.act("settings.open", { page: "layout" })
            return true
        }
        if (a.ops) {
            if (a.ops.length > 0) Store.apply(a.ops)
            return false
        }
        if (a.action) {
            Store.act(a.action, a.args)
            return false
        }
        var op = { set: a.key, value: a.value }
        // An output's own entry is what stands there: change that one.
        var c = bars ? bars.config : null, out = bars ? bars.outName : ""
        if (out !== "" && c && c.outputs && c.outputs[out] && c.outputs[out][a.key] !== undefined) op.output = out
        Store.apply([op])
        return false
    }
}
