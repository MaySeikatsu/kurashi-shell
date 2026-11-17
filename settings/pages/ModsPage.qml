import QtQuick
import QtQuick.Controls.Basic as QQC
import "../core"
import "../components"

// Mods page (MODS.md, "The Settings Mods page"; UX brief, settings 5): one entry per mod from the daemon's `mods` document.
// The state shown is always the daemon's. Load adds a mod's page to Settings and Remove from Settings takes it away again
// (`mod.load`, `mod.unload`); the switch asks for `mod.enable` / `mod.disable`. A refused request stays visible under its
// mod until the mod changes state; an invalid mod says what is wrong with its manifest. The rows are built from the mod ids
// and read their own entry live, so a state change updates its row in place and the focus on it stays where it is.
Flickable {
    id: p
    // Kinetic wheel and a grabbable scrollbar (session 17, docs/ux/settings.md).
    KineticWheel { view: p }
    // W94: a row's Check or switch reached by Tab comes into view.
    FocusFollow { id: follow; view: p }
    QQC.ScrollBar.vertical: PageScrollBar {}
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

    // "New mod…" opens the Mod Editor (W94); back from it, the focus returns to that row.
    signal newRequested()
    function focusNew() { Qt.callLater(function () { newBtn.forceActiveFocus() }) }
    // W94: a mod's own check (`mod.check {id}`, the ruleset the Mod Editor shows): mod id -> {report} or {error}, and the
    // ids being checked. A check changes nothing, so it goes as a plain request (not counted as an applied change).
    property var checks: ({})
    property var checking: ({})
    // `row` (optional): the mod's row, brought into view with its result once the answer is in.
    function check(id, row) {
        var c = Object.assign({}, checking)
        c[id] = true
        checking = c
        Store.request({ t: "act", action: "mod.check", args: { id: id } }, function (m) {
            var r = Object.assign({}, p.checks)
            r[id] = m.t === "done" ? { report: m.data || null } : { error: Store.actError(m, "settings.err.unknown_action") }
            p.checks = r
            var d = Object.assign({}, p.checking)
            delete d[id]
            p.checking = d
            if (row) Qt.callLater(function () { follow.reveal(row) })
        })
    }
    // Public so the test hooks can drive the page like a click would.
    function setEnabled(id, on) { request(on ? "mod.enable" : "mod.disable", id) }
    // I593 (MODS.md "Host programs"): a mod that runs a program of its own is switched on only after the page said
    // which program and the user said yes. `asking` is that mod's id; the switch stays off until the answer.
    property string asking: ""
    function programs(m) { return ((m && m.hosts) || []).map(function (x) { return x.exec }).join(", ") }
    function wish(id, on) {
        if (on && programs(Store.modEntry(id)) !== "") { asking = id; return }
        asking = ""
        setEnabled(id, on)
    }
    function answer(yes) {
        var id = asking
        asking = ""
        if (yes && id !== "") setEnabled(id, true)
    }
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
    // (read from the Store, not `entries`: a handler of Store.modsChanged may run before that binding is renewed, W94)
    function stateOf(id) {
        var m = Store.modEntry(id)
        return m ? m.state : ""
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
        var list = ((Store.mods && Store.mods.mods) || []).map(function (m) { return m.id })
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
    // I592: a mod that is switched on and waits (K158: a use it requires is not there) says for what: the reason's text
    // and the use's own name, which is an identifier and not prose.
    function waits(m) {
        return (m.errors || []).map(function (e) {
            var text = I18n.tr(e.key)
            return e.key === "mods.uses.missing" && e.detail ? text + ": " + e.detail : text
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
        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            dim: true
            text: I18n.tr("settings.ui.mods_help")
        }
        // W94: the Mod Editor (docs/ux/mod-editor.md), at the list's top.
        Item {
            width: parent.width
            height: newBtn.height
            Label {
                anchors.left: parent.left
                anchors.right: newBtn.left
                anchors.rightMargin: Theme.pad
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                dim: true
                font.pixelSize: Theme.fs - 1
                text: I18n.tr("mods.new.intro")
            }
            Button {
                id: newBtn
                objectName: "mods-new"
                anchors.right: parent.right
                label: I18n.tr("mods.new.row")
                onClicked: p.newRequested()
            }
        }
        Label {
            visible: p.forcedLoaded !== "" || p.forcedEnabled !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            dim: true
            font.pixelSize: Theme.fs - 2
            text: "⊘ " + (p.forcedLoaded !== "" ? p.forcedLoaded : p.forcedEnabled)
        }
        Label {
            visible: p.loaded && p.entries.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            dim: true
            text: I18n.tr("settings.ui.mods_empty")
        }
        Label {
            visible: !p.loaded && !Store.live
            dim: true
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
                            objectName: "mod-check:" + entry.modelData
                            label: I18n.tr("mods.new.check")
                            accessibleName: I18n.tr("mods.new.check") + ": " + I18n.tr(entry.mod.name)
                            enabled: Store.live && !p.checking[entry.modelData]
                            onClicked: p.check(entry.modelData, entry)
                        }
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
                                onToggled: v => {
                                    p.wish(entry.modelData, v)
                                    if (p.asking === entry.modelData) Qt.callLater(function () { askYes.forceActiveFocus() })
                                }
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
                            Label {
                                font.bold: true
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
                        Label {
                            visible: text !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            dim: true
                            font.pixelSize: Theme.fs - 1
                            text: entry.mod.description ? I18n.tr(entry.mod.description) : ""
                        }
                        Label {
                            visible: text !== ""
                            dim: true
                            font.pixelSize: Theme.fs - 2
                            text: p.facts(entry.mod)
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            dim: true
                            font.pixelSize: Theme.fs - 2
                            text: I18n.tr("settings.ui.mod_caps") + ": " + Store.joinedWords(entry.mod.capabilities, "settings.ui.cap.")
                                + "    " + I18n.tr("settings.ui.mod_adds") + ": " + (p.adds(entry.mod) || I18n.tr("settings.ui.mod_none"))
                        }
                        // I593: a mod with a program of its own says so in its row too (the row listed capabilities only).
                        Label {
                            visible: text !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: Theme.warning
                            font.pixelSize: Theme.fs - 2
                            text: p.programs(entry.mod) !== ""
                                ? I18n.fmt("settings.mods.runs_program", { program: p.programs(entry.mod) }) : ""
                        }
                        // "Running now" (K25, I48): what the mod runs for, or "Not running". Not in the sidebar.
                        Label {
                            visible: entry.isLoaded
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: entry.mod.running ? Theme.fg : Theme.dim
                            font.pixelSize: Theme.fs - 2
                            text: (entry.mod.running_reasons || []).length > 0
                                ? I18n.fmt("settings.mods.running_now", { reasons: Store.joinedWords(entry.mod.running_reasons, "") })
                                : I18n.tr("settings.mods.not_running")
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }
                    }
                }
                // I593: the question before a mod with a program is switched on. Escape or Keep off leaves it off.
                Column {
                    visible: p.asking === entry.modelData
                    width: parent.width
                    spacing: 4
                    // The question is under the row: brought into view with its keys, whatever asked (switch or action).
                    onVisibleChanged: if (visible) Qt.callLater(function () { follow.reveal(askRow) })
                    Label {
                        objectName: "mod-ask:" + entry.modelData
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: I18n.fmt("settings.mods.program_ask", { name: I18n.tr(entry.mod.name), program: p.programs(entry.mod) })
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                    Row {
                        spacing: 4
                        id: askRow
                        Button {
                            id: askYes
                            objectName: "mod-ask-yes:" + entry.modelData
                            primary: true
                            label: I18n.tr("settings.mods.program_yes")
                            onClicked: { p.answer(true); tog.forceActiveFocus() }
                            Keys.onEscapePressed: event => { p.answer(false); tog.forceActiveFocus(); event.accepted = true }
                        }
                        Button {
                            objectName: "mod-ask-no:" + entry.modelData
                            label: I18n.tr("settings.mods.program_no")
                            onClicked: { p.answer(false); tog.forceActiveFocus() }
                            Keys.onEscapePressed: event => { p.answer(false); tog.forceActiveFocus(); event.accepted = true }
                        }
                    }
                }
                // I592: switched on, and waiting for something it requires.
                Label {
                    objectName: "mod-waits:" + entry.modelData
                    visible: entry.isLoaded && (entry.mod.errors || []).length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.warning
                    font.pixelSize: Theme.fs - 2
                    text: visible ? p.waits(entry.mod) : ""
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                Label {
                    visible: entry.invalid
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 2
                    text: "✕ " + p.problems(entry.mod)
                }
                Label {
                    visible: entry.failure !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 2
                    text: "✕ " + I18n.tr("settings.ui.mods_failed") + ": " + entry.failure
                }
                // I605: where the mod lives, as a link that opens the folder (shown with its check: an author's line, not
                // every row's).
                LinkText {
                    objectName: "mod-folder:" + entry.modelData
                    visible: !!p.checks[entry.modelData] && !!entry.mod.dir
                    text: I18n.fmt("mods.folder", { path: String(entry.mod.dir || "") })
                    onActivated: Store.act("mod.open_folder", { id: entry.modelData })
                }
                // Its check, once asked: "Every rule is met", or the findings with where and what (the editor's wording).
                CheckReport {
                    readonly property var result: p.checks[entry.modelData] || null
                    visible: !!result && !!result.report
                    width: parent.width
                    compact: true
                    report: result ? result.report : null
                    summaryName: "mod-check-result:" + entry.modelData
                }
                Label {
                    readonly property var result: p.checks[entry.modelData] || null
                    visible: !!result && !!result.error
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 2
                    text: result && result.error ? "✕ " + result.error : ""
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
