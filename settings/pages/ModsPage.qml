import QtQuick
import "../core"
import "../components"

// Mods page (MODS.md, "The Settings Mods page"; UX brief, settings 5): one entry per mod from the daemon's `mods` document.
// The state shown is always the daemon's. Load adds a mod's page to Settings and Remove from Settings takes it away again
// (`mod.load`, `mod.unload`); the switch asks for `mod.enable` / `mod.disable`. A refused request stays visible under its
// mod until the mod changes state; an invalid mod says what is wrong with its manifest. The rows are built from the mod ids
// and read their own entry live, so a state change updates its row in place and the focus on it stays where it is.
Flickable {
    id: p
    // mod id -> {text, state}: why its last request was refused (the catalog text, or the generic line with its code) and
    // the state the row had then. The line goes once the row changes state, and on any change that goes through (B8).
    property var failures: ({})
    readonly property bool loaded: Store.mods.mods !== undefined
    readonly property var entries: loaded ? Store.mods.mods : []
    // The mod ids in the daemon's order: rebuilt only when a mod is added, removed or moved (refreshIds).
    property var ids: []
    property string idsSig: ""
    // Why the loaded list and the enabled list are forced by a layer (nix): their controls are inert, and say so.
    readonly property string forcedLoaded: Store.forcedReason("mods.loaded")
    readonly property string forcedEnabled: Store.forcedReason("mods.enabled")

    contentWidth: width
    contentHeight: col.implicitHeight + Theme.pad * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Public so the test hooks can drive the page like a click would.
    function setEnabled(id, on) { request(on ? "mod.enable" : "mod.disable", id) }
    function load(id) { request("mod.load", id) }
    function unload(id) { request("mod.unload", id) }
    function request(action, id) {
        var f = Object.assign({}, failures)
        delete f[id]
        failures = f
        Store.act(action, { id: id }, function (m) {
            if (m.t === "done") return
            var g = Object.assign({}, p.failures)
            g[id] = { text: Store.actError(m, "settings.err.unknown_action"), state: stateOf(id) }
            p.failures = g
        })
    }
    function stateOf(id) {
        for (var i = 0; i < entries.length; i++) if (entries[i].id === id) return entries[i].state
        return ""
    }
    // Drops every refusal whose row is no longer in the state it was refused in.
    function pruneFailures() {
        var f = Object.assign({}, failures)
        var dropped = false
        for (var id in f) {
            if (stateOf(id) !== f[id].state) { delete f[id]; dropped = true }
        }
        if (dropped) failures = f
    }
    function refreshIds() {
        var list = entries.map(function (m) { return m.id })
        var sig = list.join("\n")
        if (sig !== idsSig) {
            idsSig = sig
            ids = list
        }
    }
    // Why an invalid mod cannot run: the catalog text of its reason and the file it concerns. The parser's or the OS's own
    // detail is English and stays out of the page. A path the text already names ("mod.toml is missing") is not repeated.
    function problems(m) {
        return (m.errors || []).map(function (e) {
            var text = I18n.tr(e.key)
            return e.path && text.indexOf(e.path) < 0 ? text + " (" + e.path + ")" : text
        }).join("\n")
    }
    Component.onCompleted: refreshIds()
    Connections {
        target: Store
        function onModsChanged() { p.refreshIds(); p.pruneFailures() }
        function onChangeApplied() { p.failures = ({}) }
    }
    // "v0.1.0 · tier native · cost low": the facts the manifest gives, and no placeholder for the rest.
    function facts(m) {
        var parts = []
        if (m.version) parts.push("v" + m.version)
        if (m.tier) parts.push(I18n.tr("settings.ui.tier." + m.tier))
        if (m.cost) parts.push(I18n.tr("settings.ui.cost." + m.cost))
        return parts.join(" · ")
    }
    // The contributions as words, joined: "a bar widget, a face in the Island".
    function adds(m) {
        return (m.provides || []).map(function (x) { return Store.addsLabel(x) }).join(", ")
    }

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        width: p.width - 2 * Theme.pad
        spacing: Theme.pad

        PageHeader {
            width: parent.width
            text: I18n.tr("settings.ui.mods")
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.mods_help")
        }
        Text {
            visible: p.forcedLoaded !== "" || p.forcedEnabled !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs - 2
            font.family: Theme.fam(text, Theme.families)
            text: "⊘ " + (p.forcedLoaded !== "" ? p.forcedLoaded : p.forcedEnabled)
        }
        Text {
            visible: p.loaded && p.entries.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.mods_empty")
        }
        Text {
            visible: !p.loaded && !Store.live
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.ui.disconnected")
        }

        Repeater {
            model: p.ids
            delegate: Column {
                id: entry
                // The mod's id; its entry is read live from the `mods` document (Store.modEntry).
                required property string modelData
                readonly property var mod: Store.modEntry(entry.modelData) || ({})
                readonly property bool invalid: entry.mod.state === "invalid"
                // Loaded: its page is in Settings, on or off. Available: detected only, with a Load.
                readonly property bool isLoaded: entry.mod.state === "enabled" || entry.mod.state === "disabled"
                readonly property bool available: entry.mod.state === "available"
                readonly property string failure: p.failures[entry.modelData] ? p.failures[entry.modelData].text : ""
                width: col.width
                spacing: 4

                Item {
                    width: parent.width
                    height: Math.max(info.implicitHeight, ctl.height)
                    Row {
                        id: ctl
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: Theme.gap
                        Button {
                            visible: entry.available
                            primary: true
                            label: I18n.tr("settings.mods.load")
                            enabled: Store.live && p.forcedLoaded === ""
                            onClicked: p.load(entry.modelData)
                        }
                        Button {
                            visible: entry.isLoaded
                            label: I18n.tr("settings.mods.unload")
                            enabled: Store.live && p.forcedLoaded === ""
                            onClicked: p.unload(entry.modelData)
                        }
                        Item {
                            visible: entry.isLoaded
                            width: tog.width
                            height: Theme.controlH
                            Toggle {
                                id: tog
                                objectName: "mod:" + entry.modelData
                                label: I18n.tr(entry.mod.name)
                                anchors.verticalCenter: parent.verticalCenter
                                checked: entry.mod.state === "enabled"
                                enabled: Store.live && p.forcedEnabled === ""
                                onToggled: v => p.setEnabled(entry.modelData, v)
                            }
                        }
                    }
                    Column {
                        id: info
                        anchors.left: parent.left
                        anchors.right: ctl.left
                        anchors.rightMargin: Theme.pad
                        spacing: 3
                        Row {
                            spacing: Theme.gap
                            Text {
                                color: Theme.fg
                                font.pixelSize: Theme.fs
                                font.bold: true
                                font.family: Theme.fam(text, Theme.families)
                                text: I18n.tr(entry.mod.name)
                            }
                            Chip {
                                text: I18n.tr("settings.ui.mod_state." + entry.mod.state)
                                edge: entry.invalid ? Theme.error : Theme.outline
                                fg: entry.mod.state === "enabled" ? Theme.fg : Theme.dim
                            }
                            Chip {
                                visible: entry.mod.shadows_bundled === true
                                text: I18n.tr("settings.ui.mod_shadows")
                            }
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 1
                            font.family: Theme.fam(text, Theme.families)
                            text: entry.mod.description ? I18n.tr(entry.mod.description) : ""
                        }
                        Text {
                            visible: text !== ""
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 2
                            font.family: Theme.fam(text, Theme.families)
                            text: p.facts(entry.mod)
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.dim
                            font.pixelSize: Theme.fs - 2
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr("settings.ui.mod_caps") + ": " + Store.joinedWords(entry.mod.capabilities, "settings.ui.cap.")
                                + "    " + I18n.tr("settings.ui.mod_adds") + ": " + (p.adds(entry.mod) || I18n.tr("settings.ui.mod_none"))
                        }
                        // "Running now" (K25): one of the mod's services has a subscriber. Not in the sidebar.
                        Text {
                            visible: entry.isLoaded
                            width: parent.width
                            color: entry.mod.running ? Theme.fg : Theme.dim
                            font.pixelSize: Theme.fs - 2
                            font.family: Theme.fam(text, Theme.families)
                            text: I18n.tr(entry.mod.running ? "settings.mods.running_yes" : "settings.mods.running_no")
                        }
                    }
                }
                Text {
                    visible: entry.invalid
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: "✕ " + p.problems(entry.mod)
                }
                Text {
                    visible: entry.failure !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: "✕ " + I18n.tr("settings.ui.mods_failed") + ": " + entry.failure
                }
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.containerHigh
                }
            }
        }
    }
}
