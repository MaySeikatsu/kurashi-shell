pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// IPC client over the kurashi socket (NDJSON, PROTOCOL v1). Holds the daemon's documents and
// correlates request ids; no business logic (rule 1). The only derived data are display helpers
// (inert reasons from schema couplings), never decisions about what a value may be.
Singleton {
    id: root
    // PROTOCOL §1: `$XDG_RUNTIME_DIR/kurashi/ipc.sock`, overridden by `KURASHI_SOCKET` — the same rule
    // as kurashid and the CLI. (Reading only the override left every live start disconnected.)
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
    // key -> error text of the last rejected apply touching it (cleared by the next apply of it, and by any
    // change that goes through: a refusal is stale once something else succeeded, B8)
    property var rowErrors: ({})
    // Undo/redo/profile failures that belong to no row.
    property string notice: ""
    // Undo and redo availability is the daemon's `config.history` (K27): current after every change, undo,
    // redo and profile load, whoever made it. Nothing is kept here.
    readonly property bool canUndo: !!(config.history && config.history.can_undo)
    readonly property bool canRedo: !!(config.history && config.history.can_redo)
    // A change went through (an applied batch, a done action, an undo or redo).
    signal changeApplied()

    // Only these documents are subscribed, and only while this process lives (Ma).
    readonly property var subs: ["theme", "config", "schema.settings", "i18n", "svc.workspaces", "mods"]
    property var data: ({})
    property var revs: ({})
    property var pending: ({})
    property int seq: 0

    function send(m) {
        if (!sock.connected) return false
        sock.write(JSON.stringify(m) + "\n")
        sock.flush()
        return true
    }
    // Request with a reply callback (applied / rejected / done / err / preview).
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
    // A change went through: refusal lines still shown by rows are stale now (B8).
    function noteApplied() { rowErrors = ({}); changeApplied() }

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

    // key -> {pageId, row} of a schema row, or null: search jumps and the IPC hook.
    function rowOf(key) {
        var pages = schema.pages || []
        for (var i = 0; i < pages.length; i++)
            for (var j = 0; j < pages[i].sections.length; j++) {
                var rows = pages[i].sections[j].rows
                for (var k = 0; k < rows.length; k++) if (rows[k].key === key) return { pageId: pages[i].id, row: rows[k] }
            }
        return null
    }
    // key -> label i18n key, for naming the keys a coupling points at.
    function labelOf(key) {
        var h = rowOf(key)
        return h ? h.row.label : key
    }

    // Why a row is inert or not in effect yet: [{kind, text}]. The daemon decides and says so on the
    // provenance (reason, inert_by; K21). This only words it, from the schema coupling that names
    // inert_by. kind "pending" (saved, waits for a restart) leaves the row editable.
    function inertReasons(row, output) {
        var out = []
        var p = prov(row.key, output)
        if (p && p.forced_by) {
            // forced_by is a config key (a11y coupling) or a layer name (nix, capability).
            var by = rowOf(p.forced_by) ? I18n.tr(labelOf(p.forced_by)) : p.forced_by
            var r = p.reason ? I18n.fmt(p.reason, { key: by, name: p.forced_by }) : ""
            out.push({ kind: "forced", text: r || I18n.tr("settings.ui.forced_by") + " " + by })
        }
        if (p && p.reason === "settings.inert.requires") {
            for (var j = 0; j < row.couplings.length; j++) {
                var req = row.couplings[j]
                if (req.kind !== "requires" || req.key !== p.inert_by) continue
                out.push({ kind: "requires", text: I18n.fmt(
                    req.op === "eq" ? req.reason : "settings.ui.requires_ne",
                    { key: I18n.tr(labelOf(req.key)), value: displayValue(req.value) }) })
                break
            }
        } else if (p && p.reason === "settings.pending.restart") {
            out.push({ kind: "pending", text: I18n.tr("settings.pending.restart") })
        }
        for (var i = 0; i < row.couplings.length; i++) {
            var c = row.couplings[i]
            if (c.kind === "overridden_by") {
                // Already explained by the forced line above.
                if (valueOf(c.key, output) === true && !(p && p.forced_by === c.key))
                    out.push({ kind: "overridden_by", text: I18n.fmt(c.reason, { key: I18n.tr(labelOf(c.key)) }) })
            } else if (c.kind === "capability") {
                if (p && p.forced_by === "capability")
                    out.push({ kind: "capability", text: I18n.fmt(c.reason, { name: c.name }) })
            }
        }
        return out
    }
    function displayValue(v) {
        if (v === true) return I18n.tr("settings.ui.on")
        if (v === false) return I18n.tr("settings.ui.off")
        if (Array.isArray(v)) return v.join(", ")
        return String(v)
    }

    // --- writes --------------------------------------------------------------------------------
    function apply(ops, cb) {
        var keys = ops.map(function (o) { return o.set || o.reset })
        var errs = Object.assign({}, rowErrors)
        keys.forEach(function (k) { delete errs[k] })
        rowErrors = errs
        notice = ""
        return request({ t: "apply", ops: ops }, function (m) {
            if (m.t === "applied") noteApplied()
            if (m.t === "rejected") {
                var e = Object.assign({}, rowErrors)
                var attempted = {}
                ops.forEach(function (o) { if (o.set) attempted[o.set] = o.value })
                m.errors.forEach(function (er) {
                    e[er.key] = errorText(er) + (attempted[er.key] !== undefined ? " (" + displayValue(attempted[er.key]) + ")" : "")
                })
                rowErrors = e
            }
            if (cb) cb(m)
        })
    }
    function setValue(key, value, output) {
        var op = { set: key, value: value }
        if (output) op.output = output
        return apply([op])
    }
    function reset(key, output) {
        var op = { reset: key }
        if (output) op.output = output
        return apply([op])
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
        case "config": config = v; break
        case "schema.settings": schema = v; break
        case "i18n": i18n = v; break
        case "svc.workspaces": workspaces = v; break
        case "mods": mods = v; break
        }
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
        } else if (m.t === "snap") {
            data[m.doc] = m.data
            revs[m.doc] = m.rev
            publish(m.doc)
            live = true
        } else if (m.t === "patch") {
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
