pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Thin view-model over the kurashi IPC socket (NDJSON). All state lives in the daemon.
Singleton {
    id: root

    property var theme: ({})
    property var clock: ({})
    property var workspaces: ({})
    property var audio: ({})
    property var media: ({})
    property var island: ({})
    property var ui: ({})
    property var mods: ({})
    property string audioOrigin: ""
    property bool online: false

    readonly property var tokens: (theme && theme.tokens) ? theme.tokens : ({})
    function tok(k, d) { var v = tokens[k]; return v === undefined ? d : v }
    function bezier(k, d) { var c = tok(k, d); return [c[0], c[1], c[2], c[3], 1, 1] }
    function fam(t, f) { if (!f || f.length < 2) return ""; return /[\u3000-\u30ff\u4e00-\u9fff]/.test(t || "") ? f[1] : f[0] }
    function color(k, d) { return Qt.color(tok(k, d)) }

    readonly property var subs: ["theme", "svc.clock", "svc.workspaces", "svc.audio", "svc.media",
                                 "runtime.island.main", "runtime.ui", "mods.probe"]
    property var data: ({})
    property var revs: ({})
    property int seq: 0

    function send(m) {
        if (!sock.connected) return
        sock.write(JSON.stringify(m) + "\n")
        sock.flush()
    }
    function act(a) { send({ t: "act", id: "a" + (++seq), action: a }) }
    function intent(key, value, origin) {
        send({ t: "intent", key: key, value: value, origin: origin, coalesce: true })
    }

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
        case "svc.clock": clock = v; break
        case "svc.workspaces": workspaces = v; break
        case "svc.audio": audio = v; break
        case "svc.media": media = v; break
        case "runtime.island.main": island = v; break
        case "runtime.ui": ui = v; break
        case "mods.probe": mods = v; break
        }
    }

    function handle(line) {
        if (!line) return
        var m
        try { m = JSON.parse(line) } catch (e) { return }
        if (m.t === "welcome") {
            retry.interval = 250
            online = true
            for (var i = 0; i < subs.length; i++) send({ t: "sub", id: "s" + i, doc: subs[i] })
        } else if (m.t === "snap") {
            data[m.doc] = m.data
            revs[m.doc] = m.rev
            publish(m.doc)
        } else if (m.t === "patch") {
            if (revs[m.doc] === undefined || m.rev !== revs[m.doc] + 1) {
                if (revs[m.doc] === undefined || m.rev > revs[m.doc]) send({ t: "resync", doc: m.doc })
                return
            }
            revs[m.doc] = m.rev
            data[m.doc] = merge(data[m.doc], m.ops)
            if (m.doc === "svc.audio") audioOrigin = m.origin || ""
            publish(m.doc)
        } else if (m.t === "ping") {
            send({ t: "pong" })
        }
    }

    Socket {
        id: sock
        path: Quickshell.env("KURASHI_SOCKET")
        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handle(data)
        }
        onConnectedChanged: {
            if (connected) {
                root.send({ t: "hello", v: 1, client: "frontend", caps: ["intents", "resync"] })
            } else {
                root.online = false
                retry.start()   // keep last state, reconnect with backoff
            }
        }
        onError: retry.start()
    }

    // Runs only while disconnected (Ma): 250 ms -> 4 s backoff.
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
