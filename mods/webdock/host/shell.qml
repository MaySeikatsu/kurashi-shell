//@ pragma ShareOpenGLContexts
//@ pragma DefaultEnv QTWEBENGINE_CHROMIUM_FLAGS = --disable-background-networking --disable-component-update --disable-domain-reliability --no-pings
// The web dock's web host (MODS.md "Host processes" and "Web dock"; K38, K39): a Quickshell config with QtWebEngine,
// which the daemon starts and stops. It connects with the scope the daemon handed it (KURASHI_SCOPE_MOD,
// KURASHI_SCOPE_TOKEN), watches `mod.webdock`, `theme` and `i18n`, and draws the card. The daemon owns every mode and
// every pin; the host draws what `mod.webdock` says and reports what the engine does. Run by the patched Quickshell:
//   qs-webengine -p mods/webdock/host/shell.qml
// Chromium's switches are the pragma's default; a test that wants the net log sets QTWEBENGINE_CHROMIUM_FLAGS itself.
import QtQuick
import Quickshell
import "core"

ShellRoot {
    id: root

    // The daemon's document and what follows from it. Empty until its first snapshot.
    readonly property var doc: Store.docs["mod.webdock"] || ({})
    readonly property var pins: doc.pins || []
    readonly property var geo: doc.geometry || ({})
    readonly property string shownId: doc.shown || ""
    readonly property var shownPin: pinById(shownId)
    readonly property bool cardOpen: doc.mode === "extended" && !!shownPin && shownPin.kind === "web"
    readonly property var keepWeb: keepList()

    function pinById(id) {
        for (var i = 0; i < pins.length; i++)
            if (pins[i].id === id) return pins[i]
        return null
    }
    // The web pins the daemon keeps loaded, most recently shown first; a pin that is no longer served is not kept.
    function keepList() {
        var out = []
        var keep = doc.keep || []
        for (var i = 0; i < keep.length; i++) {
            var p = pinById(keep[i])
            if (p && p.kind === "web") out.push(keep[i])
        }
        return out
    }
    // Reports and actions go to the daemon over the scoped connection. A refusal is logged; the document is the truth.
    function report(action, args) {
        Store.act(action, args, function (done, err) {
            if (err) console.warn("webdock: " + action + " refused: " + err.kind + " " + err.msg)
        })
    }

    Watch { doc: "mod.webdock" }
    Watch { doc: "theme" }
    Watch { doc: "i18n" }

    // The daemon did not issue this scope (goodbye scope): nothing can be served, and a host the daemon does not
    // know must not linger. The daemon starts a new one with a new token when it needs one.
    Connections {
        target: Store
        function onRefusedChanged() {
            if (Store.refused !== "") {
                console.warn("webdock: the daemon refused this host's scope; exiting")
                Qt.quit()
            }
        }
    }

    Profiles {
        id: profiles
        pins: root.pins
        storageRoot: root.doc.dirs ? (root.doc.dirs.profiles || "") : ""
        report: root.report
    }

    WebCard {
        id: card
        pins: root.pins
        keepWeb: root.keepWeb
        shownId: root.shownId
        open: root.cardOpen
        edge: root.doc.edge || "right"
        size: root.doc.size || "phone"
        strip: root.geo.strip || 56
        phoneWidth: root.geo.width || 412
        largePct: root.geo.large || 90
        output: root.doc.output || ""
        profiles: profiles
        report: root.report
    }
}
