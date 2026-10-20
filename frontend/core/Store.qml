pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// IPC client over the kurashi socket (NDJSON, PROTOCOL v1). Holds the daemon's state, nothing else.
// Documents are subscribed on demand (watch/unwatch, refcounted) so the daemon only runs services
// something actually renders (Ma).
Singleton {
    id: root
    // PROTOCOL §1: `$XDG_RUNTIME_DIR/kurashi/ipc.sock`, overridden by `KURASHI_SOCKET` — the same rule
    // as kurashid and the CLI. (Reading only the override left every live start disconnected.)
    readonly property string socketPath: Quickshell.env("KURASHI_SOCKET")
        || ((Quickshell.env("XDG_RUNTIME_DIR") || "") + "/kurashi/ipc.sock")
    // A mod's host process (MODS.md "Host processes", K38) connects with the scope the daemon handed it;
    // the shell has none, and its hello stays as it was.
    readonly property string scopeMod: Quickshell.env("KURASHI_SCOPE_MOD") || ""
    readonly property string scopeToken: Quickshell.env("KURASHI_SCOPE_TOKEN") || ""
    readonly property string clientName: Quickshell.env("KURASHI_CLIENT") || "frontend"
    // Set by `goodbye` with reason `scope` (PROTOCOL §2): the daemon did not issue this token, so
    // retrying cannot succeed and the reconnect loop stops.
    property string refused: ""

    // Reactive document map: Store.docs["svc.media"]. Reassigned (shallow copy) on every change so
    // bindings re-evaluate; a doc that is not watched, or that the daemon does not serve, is absent.
    property var docs: ({})

    // Socket is up and welcomed.
    property bool connected: false
    // Connected AND at least one snapshot arrived since the last welcome (state is current again).
    property bool live: false
    property string instance: ""

    property var revs: ({})
    property var wanted: ({})       // doc -> watcher count
    property var pending: ({})      // request id -> callback (act) | {kind, cb} (query)
    property var latestQuery: ({})  // kind -> id of the newest query (older results are dropped)
    property int seq: 0
    property var cur: null          // the live Socket instance

    function send(m) {
        var sock = root.cur
        if (!sock || !sock.connected) return
        sock.write(JSON.stringify(m) + "\n")
        sock.flush()
    }

    // First watcher subscribes, last unwatch unsubscribes (the daemon then stops the backing
    // service). Safe to call while disconnected: the welcome subscribes everything wanted.
    function watch(doc) {
        var n = (wanted[doc] || 0) + 1
        wanted[doc] = n
        if (n === 1 && connected) send({ t: "sub", id: "s:" + doc, doc: doc })
    }
    function unwatch(doc) {
        var n = wanted[doc] || 0
        if (n <= 0) return
        if (n > 1) { wanted[doc] = n - 1; return }
        delete wanted[doc]
        if (connected) send({ t: "unsub", doc: doc })
        delete revs[doc]
        // The value leaves `docs` on the next turn, not here: unwatch runs when a Watch is destroyed, which a Loader's
        // active or sourceComponent change does inside the bindings that read `docs` (a view closing). Writing `docs`
        // from there re-enters those bindings: "Binding loop detected" (Stage ui, wantedKind). A re-watch in between wins.
        Qt.callLater(function () { if (!wanted[doc]) setDoc(doc, undefined) })
    }
    function setDoc(doc, v) {
        var d = Object.assign({}, docs)
        if (v === undefined) delete d[doc]
        else d[doc] = v
        docs = d
    }

    // Actions: cb(done, err). `done` is the daemon's reply (done.data may carry a result), `err`
    // the {kind, msg} of a failure; exactly one is non-null. cb is optional.
    // Config writes from a view (row 134): one atomic `apply`; cb(null) when applied, cb(errors) when rejected — the
    // errors are `[{key, code, msg}]`, `code` an i18n key — and cb([{code:"disconnected"}]) without a daemon.
    function apply(ops, cb) {
        var id = "c" + (++seq)
        if (cb) pending[id] = { apply: cb }
        if (!connected) { if (cb) { delete pending[id]; cb([{ code: "disconnected" }]) } return }
        send({ t: "apply", id: id, ops: ops })
    }
    function act(action, args, cb) {
        var id = "a" + (++seq)
        if (cb) pending[id] = cb
        if (!connected) { fail(id, { kind: "unavailable", msg: "disconnected" }); return }
        send({ t: "act", id: id, action: action, args: args || {} })
    }
    // Queries: cb(items, err). Only the newest query per kind is answered; stale ids are dropped.
    function query(kind, q, cb) {
        var id = "q" + (++seq)
        latestQuery[kind] = id
        pending[id] = { kind: kind, cb: cb }
        if (!connected) { fail(id, { kind: "unavailable", msg: "disconnected" }); return }
        send({ t: "query", id: id, kind: kind, q: q })
    }
    function intent(key, value, origin) {
        send({ t: "intent", key: key, value: value, origin: origin, coalesce: true })
    }
    function fail(id, e) {
        var p = pending[id]
        delete pending[id]
        if (!p) return
        if (typeof p === "function") p(null, e)
        else if (p.cb) p.cb(null, e)
    }
    function failAll(e) {
        var ids = Object.keys(pending)
        for (var i = 0; i < ids.length; i++) fail(ids[i], e)
    }

    // RFC 7386 merge-patch.
    function merge(t, p) {
        if (p === null || typeof p !== "object" || Array.isArray(p)) return p
        if (t === null || typeof t !== "object" || Array.isArray(t)) t = {}
        for (var k in p) {
            if (p[k] === null) delete t[k]
            else t[k] = merge(t[k], p[k])
        }
        return t
    }

    function subscribeAll() {
        for (var doc in wanted) send({ t: "sub", id: "s:" + doc, doc: doc })
    }

    function handle(line) {
        if (!line) return
        var m
        try { m = JSON.parse(line) } catch (e) { return }
        if (m.t === "welcome") {
            retry.stop()
            retry.interval = 250
            // Revisions restart per daemon instance; after any reconnect every doc is re-subscribed
            // anyway, so a changed instance only matters for dropping what the new one may not serve.
            if (instance !== "" && m.instance !== instance) docs = ({})
            instance = m.instance || ""
            revs = ({})
            connected = true
            subscribeAll()
        } else if (m.t === "snap") {
            if (!wanted[m.doc]) return
            revs[m.doc] = m.rev
            setDoc(m.doc, m.data)
            live = true
        } else if (m.t === "patch") {
            if (!wanted[m.doc] || docs[m.doc] === undefined) return
            if (revs[m.doc] === undefined || m.rev !== revs[m.doc] + 1) {
                if (revs[m.doc] === undefined || m.rev > revs[m.doc]) send({ t: "resync", doc: m.doc })
                return
            }
            revs[m.doc] = m.rev
            setDoc(m.doc, merge(JSON.parse(JSON.stringify(docs[m.doc])), m.ops))
        } else if (m.t === "applied" || m.t === "rejected") {
            var ap = pending[m.id]
            delete pending[m.id]
            if (ap && ap.apply) ap.apply(m.t === "applied" ? null : (m.errors || []))
        } else if (m.t === "done") {
            var cb = pending[m.id]
            delete pending[m.id]
            if (typeof cb === "function") cb(m, null)
        } else if (m.t === "results") {
            var q = pending[m.id]
            delete pending[m.id]
            // Stale answers (a newer query of the same kind exists) are dropped.
            if (q && q.cb && latestQuery[q.kind] === m.id) q.cb(m.items || [], null)
        } else if (m.t === "err") {
            if (m.id && m.id.indexOf("s:") === 0) {
                // The daemon does not serve this doc: leave it absent, never retry (no storm).
                var doc = m.id.substring(2)
                delete revs[doc]
                setDoc(doc, undefined)
                live = true
            } else if (m.id) {
                fail(m.id, { kind: m.kind, msg: m.msg })
            }
        } else if (m.t === "ping") {
            send({ t: "pong" })
        } else if (m.t === "goodbye" && m.reason === "scope") {
            retry.stop()
            refused = "scope"
            console.warn("Store: the daemon refused this scope (goodbye scope); not retrying")
        }
    }

    // A Socket whose first attempt failed does not reliably retry when toggled (measured: silent
    // after the first ServerNotFound), so every attempt gets a fresh Socket instance.
    Component {
        id: sockComp
        Socket {
            id: s
            path: root.socketPath
            Component.onCompleted: { root.cur = s; connected = true }
            Component.onDestruction: if (root.cur === s) root.cur = null
            parser: SplitParser {
                splitMarker: "\n"
                onRead: data => root.handle(data)
            }
            onConnectedChanged: {
                if (root.cur !== s) return   // a replaced instance dying must not touch state
                if (connected) {
                    var hello = { t: "hello", v: 1, client: root.clientName, caps: ["intents", "resync"] }
                    if (root.scopeMod !== "" && root.scopeToken !== "")
                        hello.scope = { mod: root.scopeMod, token: root.scopeToken }
                    root.send(hello)
                } else {
                    // Keep the last state (the veil marks it stale).
                    root.connected = false
                    root.live = false
                    root.revs = ({})
                    root.failAll({ kind: "unavailable", msg: "disconnected" })
                    if (!retry.running && root.refused === "") retry.start()
                }
            }
        }
    }
    Loader { id: ld; sourceComponent: sockComp }

    // Runs only while not welcomed (Ma): 250 ms doubling to 4 s. Does not rely on error signals
    // (an attempt can fail silently): keeps ticking until the welcome arrives.
    Timer {
        id: retry
        interval: 250
        repeat: false
        onTriggered: {
            interval = Math.min(interval * 2, 4000)
            if (root.connected || root.refused !== "") return
            ld.active = false
            ld.active = true
            start()
        }
    }

    Component.onCompleted: retry.start()
}
