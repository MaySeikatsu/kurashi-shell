.pragma library
// The right-click menus' shared rows (W82, docs/ux/context-menus.md): a provider (ModuleMenu, DesktopMenu, BarMenu, the
// web host's PageMenu) picks schema rows with its own rule and turns them into TrayMenu's tree here, so every menu draws a
// setting the same way: a toggle is a check mark, a choice or a range a submenu of radio rows (a range in at most five
// steps and the value in effect), a list to pick from a submenu of check marks; a row another setting holds stays grey
// and one line under its run says why (Shōjiki). Each entry carries what it does in `act` — `{key, value}` to set,
// `{action, args}` to send, `{ops}` to apply, `{open: …}` for Settings — which TrayMenu ignores.

// The rows of `schema` (the `schema.settings` document) that `pick(page, section, row)` takes, in the schema's order.
function rowsWhere(schema, pick, lists) {
    var out = []
    if (!schema || !schema.pages) return out
    for (var i = 0; i < schema.pages.length; i++) {
        var p = schema.pages[i]
        for (var j = 0; j < p.sections.length; j++) {
            var rs = p.sections[j].rows
            for (var k = 0; k < rs.length; k++)
                if (drawable(rs[k], lists !== false) && pick(p, p.sections[j], rs[k])) out.push(rs[k])
        }
    }
    return out
}

// A row a menu can hold: a toggle, a range, a choice; a list to pick from only where `lists` (a module's own lists).
// Text, records and advanced rows stay in Settings.
function drawable(r, lists) {
    if (r.advanced === true) return false
    if (r.control === "toggle" || r.control === "slider") return true
    if (r.control === "select") return !!r.choices
    return lists && r.control === "pick_list" && !!r.choices
}

function rowOf(schema, key) {
    for (var i = 0; schema && schema.pages && i < schema.pages.length; i++)
        for (var j = 0; j < schema.pages[i].sections.length; j++) {
            var rs = schema.pages[i].sections[j].rows
            for (var k = 0; k < rs.length; k++) if (rs[k].key === key) return rs[k]
        }
    return null
}

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

// Why a row does nothing now (`p`: its provenanced entry), "" while it is live. A setting another one holds names it,
// with the value it needs where one does. `tr` is I18n.tr.
function inertWhy(schema, r, p, tr) {
    if (!p) return ""
    // A layer above the user holds it (a Nix value, a pin): who.
    if (p.forced_by) return tr("settings.source.forced").replace("{name}", String(p.forced_by))
    if (p.reason !== "settings.inert.requires") return ""
    var by = p.inert_by && rowOf(schema, p.inert_by)
    if (!by) return tr("frontend.module.held")
    var text = tr(by.label), cs = r.couplings || []
    for (var i = 0; i < cs.length; i++) {
        if (cs[i].key !== p.inert_by || cs[i].kind !== "requires" || cs[i].op !== "eq") continue
        var ch = by.choices || []
        for (var j = 0; j < ch.length; j++) if (ch[j].value === cs[i].value) text += ": " + tr(ch[j].label)
    }
    return tr("frontend.module.needs").replace("{key}", text)
}

// The rows as menu entries. `bars` is a BarConfig (the value in effect on its output: `entry(key)`), `base` the first id
// (row i takes base + i*100, its choices the next ids, its reason base + i*100 + 50), `tr` I18n.tr.
function entries(schema, list, bars, base, tr) {
    var kids = []
    var idOf = function (i, c) { return base + i * 100 + c }
    for (var i = 0; i < list.length; i++) {
        var r = list[i], p = bars ? bars.entry(r.key) : null
        var now = p && p.value !== undefined ? p.value : r.default
        var why = inertWhy(schema, r, p, tr)
        var live = why === ""
        var id = idOf(i, 0)
        if (r.control === "toggle") {
            kids.push({ id: id, label: tr(r.label), toggle: "checkmark", checked: now === true, enabled: live,
                        act: { key: r.key, value: now !== true } })
        } else if (r.control === "pick_list") {
            // A list to pick from: each choice a check mark, the list in its order with a new one at its end.
            var picked = Array.isArray(now) ? now : []
            var pk = []
            for (var pi = 0; pi < r.choices.length; pi++) {
                var v = r.choices[pi].value, on = picked.indexOf(v) >= 0
                pk.push({ id: idOf(i, pi + 1), label: tr(r.choices[pi].label), toggle: "checkmark", checked: on, enabled: live,
                          act: { key: r.key, value: on ? without(picked, v) : picked.concat([v]) } })
            }
            kids.push({ id: id, label: tr(r.label), enabled: live, children: pk })
        } else {
            var opts = r.control === "slider"
                ? stepsOf(r, now).map(function (v) { return { value: v, label: withUnit(r, v) } })
                : r.choices.map(function (c) { return { value: c.value, label: tr(c.label) } })
            var shown = String(now)
            var ch = []
            for (var j = 0; j < opts.length; j++) {
                if (opts[j].value === now) shown = opts[j].label
                ch.push({ id: idOf(i, j + 1), label: opts[j].label, toggle: "radio", checked: opts[j].value === now, enabled: live,
                          act: { key: r.key, value: opts[j].value } })
            }
            kids.push({ id: id, label: tr(r.label) + ": " + shown, enabled: live, children: ch })
        }
        // (once for a run of rows held for the one reason)
        var nextP = i + 1 < list.length && bars ? bars.entry(list[i + 1].key) : null
        if (!live && inertWhy(schema, list[i + 1] || {}, nextP, tr) !== why) kids.push({ id: id + 50, label: why, enabled: false })
    }
    return kids
}
function without(list, v) { return list.filter(function (x) { return x !== v }) }

// The `act` of entry `id` in a tree's list, or null.
function find(id, list) {
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id) return list[i].act || null
        var hit = list[i].children ? find(id, list[i].children) : null
        if (hit) return hit
    }
    return null
}

// A set as one apply op: on the output's own entry where that output has one (what stands there), else the shared one.
function setOp(bars, key, value) {
    var op = { set: key, value: value }
    var c = bars ? bars.config : null, out = bars ? bars.outName : ""
    if (out !== "" && c && c.outputs && c.outputs[out] && c.outputs[out][key] !== undefined) op.output = out
    return op
}

// Runs an `act` through `store` (Store: act, apply). Returns true when the menu is done (it left for Settings or ran an
// action that ends it: `close`), false when it stays for the next change.
function run(store, bars, a) {
    if (!a) return false
    if (a.open) {
        store.act("settings.open", a.open)
        return true
    }
    if (a.ops) {
        if (a.ops.length > 0) store.apply(a.ops)
        return false
    }
    if (a.action) {
        store.act(a.action, a.args || {})
        return a.close === true
    }
    store.apply([setOp(bars, a.key, a.value)])
    return false
}
