pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// IPC client over the kurashi socket (NDJSON, PROTOCOL v1). Holds the daemon's documents and correlates request ids;
// no business logic (rule 1). The derived data here are display helpers only: the words for a provenance layer,
// the inert reasons the schema couplings name, the list of changed keys, and a cache of cfg.why answers. What a value
// may be, and whether a change went through, is always the daemon's answer.
Singleton {
    id: root
    // PROTOCOL §1: `$XDG_RUNTIME_DIR/kurashi/ipc.sock`, overridden by `KURASHI_SOCKET` (the rule kurashid and the CLI use).
    readonly property string socketPath: Quickshell.env("KURASHI_SOCKET")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "") + "/kurashi/ipc.sock")

    property var theme: ({})
    property var config: ({})
    property var schema: ({})
    property var i18n: ({})
    property var workspaces: ({})
    property var mods: ({})
    property bool connected: false
    property bool live: false
    // key -> error text of the last rejected apply touching it (cleared by the next apply of it, and by any change
    // that goes through: a refusal is stale once something else succeeded, B8)
    property var rowErrors: ({})
    // A records row (K38): the refusal of one of its fields, {index, field, text}, shown by the editor at that field.
    property var fieldErrors: ({})
    // Undo/redo/profile failures that belong to no row.
    property string notice: ""
    // Undo and redo availability is the daemon's `config.history` (K27): current after every change, undo, redo and
    // profile load, whoever made it.
    readonly property bool canUndo: !!(config.history && config.history.can_undo)
    readonly property bool canRedo: !!(config.history && config.history.can_redo)
    // A preview taken back by undo is still the daemon's redo step; Redo stays off until a change goes through
    // (Changes sets this after its revert, every other change clears it).
    property bool redoHidden: false
    readonly property bool redoShown: canRedo && !redoHidden
    // A change went through (an applied batch, a done action, an undo or redo).
    signal changeApplied()

    // Only these documents are subscribed, and only while this process lives (Ma).
    readonly property var subs: ["theme", "config", "schema.settings", "i18n", "svc.workspaces", "mods"]
    // Documents a view asks for only while it shows them (watch/unwatch, refcounted; Ma): `docs[name]`. The theme export
    // status under its row is one (svc.theme_export, K49).
    property var docs: ({})
    property var wanted: ({})
    property var data: ({})
    property var revs: ({})
    property var pending: ({})
    property int seq: 0
    // cfg.why answers by "key|output" (PROTOCOL §5): the daemon's layers, kept until the config changes.
    property var explained: ({})
    // The user value a forced layer holds back, by "key|output" (I64 (3)): {value}, or null when the key has none. Asked
    // for every forced key on each config and schema change. Kept apart from `explained`, which a config change clears:
    // the Changed view's rows must not come and go with every change.
    property var heldUsers: ({})

    function watch(doc) {
        var n = (wanted[doc] || 0) + 1
        wanted[doc] = n
        if (n === 1 && connected) send({ t: "sub", id: "w:" + doc, doc: doc })
    }
    function unwatch(doc) {
        var n = wanted[doc] || 0
        if (n <= 0) return
        if (n > 1) { wanted[doc] = n - 1; return }
        delete wanted[doc]
        if (connected) send({ t: "unsub", doc: doc })
        delete revs[doc]
        delete data[doc]
        var d = Object.assign({}, docs)
        delete d[doc]
        docs = d
    }

    function send(m) {
        if (!sock.connected) return false
        sock.write(JSON.stringify(m) + "\n")
        sock.flush()
        return true
    }
    // Request with a reply callback (applied / rejected / done / err / preview / cfg.why).
    function request(m, cb) {
        m.id = "c" + (++seq)
        if (cb) pending[m.id] = cb
        return send(m)
    }
    function act(action, args, cb) {
        request({ t: "act", action: action, args: args || ({}) }, function (m) {
            if (m.t === "done") noteApplied()
            if (cb) cb(m)
        })
    }
    // A change went through: refusal lines still shown by rows are stale now (B8), and Redo is the daemon's again.
    function noteApplied() { rowErrors = ({}); fieldErrors = ({}); redoHidden = false; changeApplied() }

    // --- config helpers ------------------------------------------------------------------------
    // Provenanced {value, source, forced_by?, reason?}; the output entry wins when present.
    function prov(key, output) {
        var c = config
        if (output && c.outputs && c.outputs[output] && c.outputs[output][key] !== undefined)
            return c.outputs[output][key]
        return c.values ? c.values[key] : undefined
    }
    function valueOf(key, output) {
        var p = prov(key, output)
        return p === undefined ? undefined : p.value
    }
    // Outputs worth offering in the picker: those with overrides plus the ones the compositor lists.
    function outputNames() {
        var seen = {}
        var out = []
        var a = config.outputs || ({})
        for (var k in a) if (!seen[k]) { seen[k] = 1; out.push(k) }
        var w = (workspaces && workspaces.outputs) || ({})
        for (var j in w) if (!seen[j]) { seen[j] = 1; out.push(j) }
        out.sort()
        return out
    }

    // --- schema helpers ------------------------------------------------------------------------
    // key -> {pageId, row} of a schema row, or null: search jumps, deep links and the inert reasons.
    function rowOf(key) {
        var pages = schema.pages || []
        for (var i = 0; i < pages.length; i++)
            for (var j = 0; j < pages[i].sections.length; j++) {
                var rows = pages[i].sections[j].rows
                for (var k = 0; k < rows.length; k++) if (rows[k].key === key) return { pageId: pages[i].id, row: rows[k] }
            }
        return null
    }
    // A page's title by its id ("Bar", "Mods › Media"); the id itself when the schema does not list the page.
    function pageLabel(pageId) {
        var ps = schema.pages || []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].id === pageId) return I18n.pageTitle(ps[i].id, ps[i].label)
        return pageId
    }
    // key -> label i18n key, for naming the keys a coupling points at.
    function labelOf(key) {
        var h = rowOf(key)
        return h ? h.row.label : key
    }
    // Every schema row in page order: [{pageId, pageLabel, section, row}].
    function allRows() {
        var out = []
        var pages = schema.pages || []
        for (var i = 0; i < pages.length; i++)
            for (var j = 0; j < pages[i].sections.length; j++) {
                var s = pages[i].sections[j]
                for (var k = 0; k < s.rows.length; k++)
                    out.push({ pageId: pages[i].id, pageLabel: pages[i].label, section: s, row: s.rows[k] })
            }
        return out
    }
    // Whether a mod is on (`enabled`); a loaded mod that is off, and a mod not loaded, are not.
    function modEntry(id) {
        var list = (mods && mods.mods) || []
        for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
        return null
    }
    function modOn(id) {
        var m = modEntry(id)
        return !!m && m.state === "enabled"
    }

    // --- provenance words (UX brief: "Kanso profile", "you", "Nix: programs.kurashi.settings.x", "accessibility")
    function nixPath(key) { return "programs.kurashi.settings." + key }
    // Whether a layer is the Nix layer (the managed file), named either way the daemon may send it.
    function isNix(src) {
        return !!src && (src.kind === "nix" || (src.kind === "forced" && src.name === "nix"))
    }
    // A layer's source as words. `src` is {kind, name?}; the key names the Nix option path.
    function sourceName(key, src) {
        var s = src || ({})
        switch (s.kind) {
        case "default": return I18n.tr("settings.source.default")
        case "user": return I18n.tr("settings.source.user")
        case "profile": return I18n.fmt("settings.source.profile", { name: s.name || "" })
        case "theme":
            // K53: each value of the theme layer names its pack, `style:<name>` or `look:<name>`: "From the style Washi".
            var pack = /^(style|look):(.+)$/.exec(s.name || "")
            if (pack) return I18n.fmt("settings.source." + pack[1], { name: packLabel(pack[1] + "s", pack[2]) })
            return s.name ? I18n.fmt("settings.source.theme", { name: s.name }) : I18n.tr("settings.source.theme_plain")
        case "nix": return I18n.fmt("settings.source.nix", { path: nixPath(key) })
        case "forced":
            if (s.name === "nix") return I18n.fmt("settings.source.nix", { path: nixPath(key) })
            return I18n.has("settings.source.by." + s.name) ? I18n.tr("settings.source.by." + s.name)
                : I18n.fmt("settings.source.forced", { name: s.name || "" })
        }
        return s.kind || ""
    }
    // --- appearance packs (K53) ----------------------------------------------------------------------
    // The offer sources whose choices are packs with previews in `theme.previews` (its keys are these names), and the
    // action that applies a pack of a kind: it resets the user's values of that kind's keys first (the daemon decides
    // which), one undo step. A palette is a plain value.
    readonly property var packSources: ["styles", "looks", "palettes"]
    readonly property var packActions: ({ styles: "theme.style.apply", looks: "theme.look.apply" })
    function isPackRow(row) { return !!row && packSources.indexOf(row.choices_from) >= 0 }
    // A pack's name in words, from the offers of the row that picks it (a user pack without a catalogue key: its name).
    function packLabel(source, name) {
        var rows = allRows()
        for (var i = 0; i < rows.length; i++) {
            if (rows[i].row.choices_from !== source) continue
            var cs = rows[i].row.choices || []
            for (var j = 0; j < cs.length; j++) if (cs[j].value === name) return I18n.tr(cs[j].label)
        }
        return name
    }
    // A pack picked: a style or a look is applied by its action ("none" — your own — only sets the style and keeps your
    // values); anything else is a plain change. A refusal shows under the row, as an apply's does.
    function pickPack(row, name) {
        var action = packActions[row.choices_from]
        if (!action || name === "none") return setValue(row.key, name)
        clearRefusal(row.key)
        act(action, { name: name }, function (m) {
            if (m.t === "done") return
            var e = Object.assign({}, rowErrors)
            e[row.key] = actError(m, "settings.appearance.refused")
            rowErrors = e
        })
    }

    // Whether a provenance is one the user or a profile gave, or Nix did: what the Changed view lists.
    function isChangedSource(p) {
        var s = p && p.source ? p.source : ({})
        return s.kind === "user" || s.kind === "profile" || isNix(s)
    }

    // Why a row is inert or not in effect yet: [{kind, text, key}]. The daemon decides and says so on the
    // provenance (reason, inert_by; K21). This only words it, from the schema coupling that names inert_by. `key`
    // is the setting that controls this one ("" when none): the row offers a link to it. kinds "pending", "unavailable"
    // and "mod_off" keep the row editable: the value is only not in effect yet.
    function inertReasons(row, output) {
        var out = []
        var p = prov(row.key, output)
        if (p && p.forced_by) out.push({ kind: "forced", text: forcedText(p), key: rowOf(p.forced_by) ? p.forced_by : "" })
        if (p && p.reason === "settings.inert.requires") {
            for (var j = 0; j < row.couplings.length; j++) {
                var req = row.couplings[j]
                if (req.kind !== "requires" || req.key !== p.inert_by) continue
                out.push({ kind: "requires", key: req.key, text: I18n.fmt(
                    req.op === "eq" ? req.reason : "settings.ui.requires_ne",
                    { key: I18n.tr(labelOf(req.key)), value: displayValue(req.value) }) })
                break
            }
        } else if (p && p.reason === "settings.pending.restart") {
            out.push({ kind: "pending", key: "", text: I18n.tr("settings.pending.restart") })
        } else if (p && p.reason === "settings.choice.unavailable") {
            out.push({ kind: "unavailable", key: "", text: I18n.tr(p.reason) })
        } else if (p && p.reason === "mods.disabled") {
            out.push({ kind: "mod_off", key: "", text: I18n.tr(p.reason) })
        }
        for (var i = 0; i < row.couplings.length; i++) {
            var c = row.couplings[i]
            if (c.kind === "overridden_by") {
                // Already explained by the forced line above.
                if (valueOf(c.key, output) === true && !(p && p.forced_by === c.key))
                    out.push({ kind: "overridden_by", key: c.key, text: I18n.fmt(c.reason, { key: I18n.tr(labelOf(c.key)) }) })
            } else if (c.kind === "capability") {
                if (p && p.forced_by === "capability")
                    out.push({ kind: "capability", key: "", text: I18n.fmt(c.reason, { name: c.name }) })
            }
        }
        return out
    }
    // What a forced value says: the layer's reason (an i18n key that takes the layer's name), else the name.
    function forcedText(p) {
        // forced_by is a config key (a11y coupling) or a layer name (nix, capability).
        var by = rowOf(p.forced_by) ? I18n.tr(labelOf(p.forced_by)) : p.forced_by
        return p.reason ? I18n.fmt(p.reason, { key: by, name: p.forced_by }) : I18n.tr("settings.ui.forced_by") + " " + by
    }
    // Why a key is forced by a layer, or "" when none forces it (the mod lists and switches use it).
    function forcedReason(key) {
        var p = prov(key)
        return p && p.forced_by ? forcedText(p) : ""
    }
    function displayValue(v) {
        if (v === true) return I18n.tr("settings.ui.on")
        if (v === false) return I18n.tr("settings.ui.off")
        // A records value (K38) is a list of objects: name each row by its title, name or id.
        if (Array.isArray(v)) return v.map(function (x) {
            return x !== null && typeof x === "object" ? String(x.title ?? x.name ?? x.id ?? "…") : String(x)
        }).join(", ")
        return String(v)
    }
    // A refusal that belongs to an edit the user cancelled (the records form) is dropped with it.
    function clearRefusal(key) {
        var e = Object.assign({}, rowErrors)
        delete e[key]
        rowErrors = e
        var f = Object.assign({}, fieldErrors)
        delete f[key]
        fieldErrors = f
    }
    // Every page-level and per-key reset is a list of reset ops; this is the op for one key on one output.
    function resetOp(key, output) {
        var op = { reset: key }
        if (output) op.output = output
        return op
    }
    // Keys the user set (source user), on a page or everywhere: [{key, output, row}] (the Changed view and the page reset).
    function userSetEntries(pageId) {
        var out = []
        var rows = allRows()
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i]
            if (pageId !== undefined && r.pageId !== pageId) continue
            var p = config.values ? config.values[r.row.key] : undefined
            if (p && p.source && p.source.kind === "user") out.push({ key: r.row.key, output: "", row: r.row, prov: p })
            if (r.row.per_output && config.outputs)
                for (var name in config.outputs) {
                    var q = config.outputs[name][r.row.key]
                    if (q && q.source && q.source.kind === "user") out.push({ key: r.row.key, output: name, row: r.row, prov: q })
                }
        }
        return out
    }
    // --- held-back user values (I64 (3)) -------------------------------------------------------------
    // A forced layer can hold a user value back. The config document shows only the value in effect, so the user's layer
    // comes from cfg.why (PROTOCOL §5), asked for each forced key and each output it is forced on.
    function forcedEntries() {
        var out = []
        var rows = allRows()
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i]
            var p = config.values ? config.values[r.row.key] : undefined
            if (p && p.source && p.source.kind === "forced") out.push({ key: r.row.key, output: "" })
            if (r.row.per_output && config.outputs)
                for (var name in config.outputs) {
                    var q = config.outputs[name][r.row.key]
                    if (q && q.source && q.source.kind === "forced") out.push({ key: r.row.key, output: name })
                }
        }
        return out
    }
    function refreshHeld() {
        var list = forcedEntries()
        for (var i = 0; i < list.length; i++) askHeld(list[i].key, list[i].output)
    }
    function askHeld(key, output) {
        var m = { t: "cfg.explain", key: key }
        if (output) m.output = output
        var k = key + "|" + (output || "")
        request(m, function (r) {
            if (r.t !== "cfg.why") return
            // The user's layer; with an output, its own user entry comes after the global one, so the last one is in effect.
            var user = null
            for (var i = 0; i < r.layers.length; i++)
                if (r.layers[i].source && r.layers[i].source.kind === "user") user = { value: r.layers[i].value }
            var h = Object.assign({}, heldUsers)
            h[k] = user
            heldUsers = h
        })
    }
    // The provenance of the user value that a forced layer holds back for this key and output: {value, source}, or null.
    function heldUserOf(key, output) {
        var h = heldUsers[key + "|" + (output || "")]
        return h ? { value: h.value, source: { kind: "user" } } : null
    }
    // The Changed view's entry for one key on one output, or null: {prov, held}. A user value that a forced layer holds
    // back is listed as held (prov is the user's value); anything else changes the view when the user, a profile or Nix
    // sets the value in effect.
    function changedOf(key, output, p) {
        if (!p || !p.source) return null
        if (p.source.kind === "forced") {
            var h = heldUserOf(key, output)
            if (h) return { prov: h, held: true }
        }
        return isChangedSource(p) ? { prov: p, held: false } : null
    }
    // Every changed setting across pages and outputs: [{pageId, row, output, prov, held}] (the Changed view).
    function changedEntries() {
        var out = []
        var rows = allRows()
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i]
            var c = changedOf(r.row.key, "", config.values ? config.values[r.row.key] : undefined)
            if (c) out.push({ pageId: r.pageId, row: r.row, output: "", prov: c.prov, held: c.held })
            if (r.row.per_output && config.outputs)
                for (var name in config.outputs) {
                    var d = changedOf(r.row.key, name, config.outputs[name][r.row.key])
                    if (d) out.push({ pageId: r.pageId, row: r.row, output: name, prov: d.prov, held: d.held })
                }
        }
        return out
    }

    // --- explanations (cfg.explain -> cfg.why) -----------------------------------------------------
    // The layers of a key, lowest first: [{source, value, active?, reason?}]. Asked on demand (a hover, a focus on a
    // provenance chip) and kept until the config changes; the cache holds only the daemon's answers.
    function explain(key, output, cb) {
        var k = key + "|" + (output || "")
        if (explained[k] !== undefined) { if (cb) cb(explained[k]); return }
        var m = { t: "cfg.explain", key: key }
        if (output) m.output = output
        request(m, function (r) {
            if (r.t !== "cfg.why") return
            var e = Object.assign({}, explained)
            e[k] = r.layers
            explained = e
            if (cb) cb(r.layers)
        })
    }

    // --- mods, as words (UX brief, settings 5) ----------------------------------------------------
    // A catalog word for a daemon value ("cost low", a capability): the catalog text when there is one, else the value.
    function word(prefix, v) {
        var k = prefix + v
        return I18n.has(k) ? I18n.tr(k) : String(v)
    }
    function joinedWords(list, prefix) {
        if (!list || list.length === 0) return I18n.tr("settings.ui.mod_none")
        return list.map(function (x) { return word(prefix, x) }).join(", ")
    }
    // One contribution as words. A `provides` entry is "kind:id" (MODS.md); the catalog says what each kind is.
    function addsLabel(p) {
        var i = p.indexOf(":")
        var kind = i < 0 ? p : p.slice(0, i)
        var k = "settings.adds." + kind
        return I18n.has(k) ? I18n.fmt(k, { id: i < 0 ? "" : p.slice(i + 1) }) : p
    }
    // The page a contribution shows on, when Settings has one ("" when none): a face sits on the Island's page.
    function addsPage(p) {
        var kind = p.split(":")[0]
        return kind === "island-face" ? "island" : (kind === "widget" ? "bar" : "")
    }

    // --- writes --------------------------------------------------------------------------------
    function apply(ops, cb) {
        var keys = ops.map(function (o) { return o.set || o.reset })
        var errs = Object.assign({}, rowErrors)
        keys.forEach(function (k) { delete errs[k] })
        rowErrors = errs
        var fe = Object.assign({}, fieldErrors)
        keys.forEach(function (k) { delete fe[k] })
        fieldErrors = fe
        notice = ""
        return request({ t: "apply", ops: ops }, function (m) {
            if (m.t === "applied") noteApplied()
            if (m.t === "rejected") {
                var e = Object.assign({}, rowErrors)
                var f = Object.assign({}, fieldErrors)
                var attempted = {}
                ops.forEach(function (o) { if (o.set) attempted[o.set] = o.value })
                m.errors.forEach(function (er) {
                    // A records value names the row and field it is wrong at (K38): `<key>[<n>].<field>`. The editor shows
                    // it at that field; a row-level one (`<key>[<n>]`) stays on the row's line.
                    var path = /^(.*?)\[(\d+)\](?:\.([a-z0-9_]+))?$/.exec(er.key || "")
                    if (path) {
                        e[path[1]] = errorText(er)
                        if (path[3]) f[path[1]] = { index: Number(path[2]), field: path[3], text: errorText(er) }
                        return
                    }
                    e[er.key] = errorText(er) + (attempted[er.key] !== undefined ? " (" + displayValue(attempted[er.key]) + ")" : "")
                })
                rowErrors = e
                fieldErrors = f
            }
            if (cb) cb(m)
        })
    }
    // A dry run: the daemon answers `preview` {diff} and changes nothing (PROTOCOL §5).
    function dryRun(ops, cb) {
        return request({ t: "apply", ops: ops, dry_run: true }, cb)
    }
    function setValue(key, value, output) {
        var op = { set: key, value: value }
        if (output) op.output = output
        return apply([op])
    }
    function reset(key, output) {
        return apply([resetOp(key, output)])
    }
    // Text for a refused apply op. The wire `msg` is English and is never shown (UX review R.2 item 13):
    // a code without catalog text becomes the generic line with the code.
    function errorText(er) {
        // The catalog text of a code may carry {placeholders} the wire does not fill; those fall
        // back to the plain reason in settings.err.* rather than showing braces.
        var k = "settings.err." + er.code
        if (I18n.has(k)) return I18n.tr(k)
        if (I18n.has(er.code) && I18n.tr(er.code).indexOf("{") < 0) return I18n.tr(er.code)
        return I18n.fmt("settings.ui.error_code", { what: I18n.tr("settings.err.rejected_value"), code: er.code || "?" })
    }
    // Text for a refused action (an `err` frame, or a `done` that is not one): the catalog key the
    // daemon sent when it sent one (the mods' reason keys), else `what` with the wire kind as the code.
    function actError(m, what) {
        if (m.msg && I18n.has(m.msg)) return I18n.tr(m.msg)
        return I18n.fmt("settings.ui.error_code", { what: I18n.tr(what), code: m.kind || "error" })
    }
    function undo() { stepHistory("undo") }
    function redo() { stepHistory("redo") }
    // The buttons follow `config.history`, which the daemon pushes after the step; a refusal only says why.
    function stepHistory(t) {
        notice = ""
        request({ t: t }, function (m) {
            if (m.t === "applied") noteApplied()
            else if (m.t === "rejected" && m.errors.length) notice = errorText(m.errors[0])
            else notice = actError(m, t === "undo" ? "settings.err.undo" : "settings.err.redo")
        })
    }

    // --- transport -----------------------------------------------------------------------------
    // RFC 7396 merge-patch.
    function merge(t, p) {
        if (p === null || typeof p !== "object" || Array.isArray(p)) return p
        if (t === null || typeof t !== "object" || Array.isArray(t)) t = {}
        for (var k in p) {
            if (p[k] === null) delete t[k]
            else t[k] = merge(t[k], p[k])
        }
        return t
    }

    function publish(doc) {
        var v = JSON.parse(JSON.stringify(data[doc]))
        switch (doc) {
        case "theme": theme = v; break
        case "config": config = v; explained = ({}); break
        case "schema.settings": schema = v; break
        case "i18n": i18n = v; break
        case "svc.workspaces": workspaces = v; break
        case "mods": mods = v; break
        default:
            if (!wanted[doc]) return
            var d = Object.assign({}, docs)
            d[doc] = v
            docs = d
        }
        // The user values that forced layers hold back follow the config and the schema (I64 (3)).
        if (doc === "config" || doc === "schema.settings") refreshHeld()
    }

    function handle(line) {
        if (!line) return
        var m
        try { m = JSON.parse(line) } catch (e) { return }
        if (m.id !== undefined && pending[m.id]) {
            var cb = pending[m.id]
            delete pending[m.id]
            cb(m)
        }
        if (m.t === "welcome") {
            retry.interval = 250
            connected = true
            for (var i = 0; i < subs.length; i++) send({ t: "sub", id: "s" + i, doc: subs[i] })
            for (var w in wanted) send({ t: "sub", id: "w:" + w, doc: w })
        } else if (m.t === "snap") {
            data[m.doc] = m.data
            revs[m.doc] = m.rev
            publish(m.doc)
            live = true
        } else if (m.t === "patch") {
            if (data[m.doc] === undefined) return
            if (revs[m.doc] === undefined || m.rev !== revs[m.doc] + 1) {
                if (revs[m.doc] === undefined || m.rev > revs[m.doc]) send({ t: "resync", doc: m.doc })
                return
            }
            revs[m.doc] = m.rev
            data[m.doc] = merge(data[m.doc], m.ops)
            publish(m.doc)
        } else if (m.t === "ping") {
            send({ t: "pong" })
        }
    }

    Socket {
        id: sock
        path: root.socketPath
        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handle(data)
        }
        onConnectedChanged: {
            if (connected) {
                root.send({ t: "hello", v: 1, client: "settings", caps: ["resync"] })
            } else {
                // Keep last state, marked stale; revisions restart with the next session.
                root.connected = false
                root.live = false
                root.revs = ({})
                root.pending = ({})
                retry.start()
            }
        }
        onError: retry.start()
    }

    // Runs only while disconnected (Ma): 250 ms doubling to 4 s.
    Timer {
        id: retry
        interval: 250
        repeat: false
        onTriggered: {
            interval = Math.min(interval * 2, 4000)
            sock.connected = true
        }
    }

    Component.onCompleted: sock.connected = true
}
