import QtQuick
import QtQuick.Controls.Basic as QQC
import Quickshell
import "../core"
import "../components"

// The Mod Editor (W94, K154; UX brief docs/ux/mod-editor.md): a new mod described in four groups, its files and the
// ruleset's verdict beside them, live, and Create. The page holds no knowledge of its own (rule 1): the checklist is the
// daemon's points registry (`query points`), the actions are its registry (`query actions`), the files and the check are
// `mod.check {spec}` on the form as it stands, Create is `mod.new {spec}`. It only builds the spec from the form.
// Shown by a Loader while it is the page (the budget: nothing closed), so every visit starts fresh.
Flickable {
    id: p
    // Kinetic wheel and a grabbable scrollbar (session 17, docs/ux/settings.md).
    KineticWheel { view: p }
    QQC.ScrollBar.vertical: PageScrollBar {}
    // Back to the Mods page (Esc, the breadcrumb), and a page link (`mod:<id>`) after Create.
    signal leave()
    signal pageRequested(string link)

    // --- the form ----------------------------------------------------------------------------------
    property string name: ""
    property string modId: ""
    // The id follows the name until it is typed into (UX brief, What it is).
    property bool idTouched: false
    property string icon: "extension"
    property string description: ""
    property string starts: "module"
    property var parts: ["widget", "peek", "panel"]
    // point id -> the reason typed for an unticked variant; absent = the template's own line (from the draft's [skips]).
    property var reasons: ({})
    // [{kind: "doc"|"action", id, optional}]
    property var uses: []
    property string usesQuery: ""
    property string runsOn: "views"

    // --- the daemon's lists ------------------------------------------------------------------------
    property var points: []
    property var actions: []

    // --- the live check -----------------------------------------------------------------------------
    property var report: null        // the last `mod.check {spec}` answer for the form as it stands
    property string refusal: ""      // a spec the scaffold refuses: its key (mods.new.error.*), or the generic text
    property int checkSeq: 0
    property bool checking: false
    property string openFile: ""

    // --- Create -------------------------------------------------------------------------------------
    property var created: null       // {id, path, check}
    property bool creating: false
    property string createError: ""
    property bool turning: false
    property string turnError: ""
    property bool asking: false      // Esc on a form with input: "Discard this mod?"

    readonly property bool locked: created !== null
    readonly property bool typed: name !== "" || (idTouched && modId !== "") || description !== ""
    // The form's parts, from the registry: one row per part a point names (its first point), in the registry's order.
    readonly property var partRows: {
        var seen = {}, out = []
        for (var i = 0; i < points.length; i++) {
            var pt = points[i]
            if (!pt.part || seen[pt.part]) continue
            seen[pt.part] = true
            out.push({ part: pt.part, point: pt.id, fill: pt.fill, expected: pt.expected === true })
        }
        return out
    }
    // The scaffold's spec (PROTOCOL §6): `with` in the registry's order.
    readonly property var spec: {
        var s = { id: modId, name: name.trim(), icon: icon.trim(), description: description.trim(),
                  with: partRows.map(function (r) { return r.part }).filter(function (x) { return parts.indexOf(x) >= 0 }),
                  uses: uses.map(function (u) { return u.kind + ":" + u.id + (u.optional ? "?" : "") }) }
        if (runsOn === "host") s.host = "python"
        return s
    }
    readonly property string specSig: JSON.stringify(spec)
    onSpecSigChanged: if (!locked) { createError = ""; debounce.restart() }

    // The draft's files, the manifest first; [] while there is no draft.
    readonly property var files: {
        var f = report && report.files ? report.files.slice() : []
        f.sort(function (a, b) { return (a.path === "mod.toml" ? 0 : 1) - (b.path === "mod.toml" ? 0 : 1) })
        return f
    }
    // The template's [skips] lines (point id -> reason), read from the last draft's manifest: what is written when left
    // alone. Kept while a draft is refused (an id being typed), so the lines do not come and go.
    property var templateSkips: ({})
    function readSkips() {
        var out = {}
        var m = files.length && files[0].path === "mod.toml" ? files[0].text : ""
        var at = m.indexOf("\n[skips]\n")
        if (at < 0) return out
        var lines = m.slice(at + 9).split("\n")
        for (var i = 0; i < lines.length && lines[i].charAt(0) !== "["; i++) {
            var kv = /^([a-z0-9.-]+) = "(.*)"$/.exec(lines[i])
            if (kv) out[kv[1]] = kv[2]
        }
        return out
    }
    onFilesChanged: if (files.length) templateSkips = readSkips()
    // A placeable module answers for every variant (K72): the expected parts left unticked ask for a line.
    function needsReason(r) {
        return parts.indexOf("widget") >= 0 && r.expected && r.part !== "widget" && parts.indexOf(r.part) < 0
    }
    function reasonOf(point) {
        return reasons[point] !== undefined ? reasons[point] : (templateSkips[point] || "")
    }
    // Stand-in (CONTRACT-CHANGE: `spec.skips`): the scaffold writes its own line for each unticked variant and the spec
    // cannot carry one yet, so a line emptied here is judged here, as the `variant` rule would judge the manifest.
    readonly property var unanswered: {
        var out = []
        for (var i = 0; i < partRows.length; i++) {
            var r = partRows[i]
            if (needsReason(r) && reasons[r.point] !== undefined && reasons[r.point].trim() === "") out.push(r.point)
        }
        return out
    }

    // The check's lines: one per rule of the catalogue (`mods.check.<rule>`), the ones not met first.
    function ruleLines(rep) {
        if (!rep) return []
        var findings = (rep.findings || []).slice()
        if (rep === report)
            unanswered.forEach(function (pt) {
                findings.push({ rule: "variant", level: "error", at: "skips." + pt, detail: I18n.tr("mods.new.skip.reason") })
            })
        var rules = Object.keys(I18n.strings).filter(function (k) { return /^mods\.check\.[a-z_]+$/.test(k) })
            .map(function (k) { return k.slice(11) })
        var lines = rules.map(function (rule) {
            var own = findings.filter(function (f) { return f.rule === rule })
            var errors = own.filter(function (f) { return f.level === "error" })
            return { rule: rule, met: errors.length === 0, findings: own }
        })
        // A rule the catalogue does not name yet still shows, by its id.
        findings.forEach(function (f) {
            if (rules.indexOf(f.rule) < 0) { rules.push(f.rule); lines.push({ rule: f.rule, met: f.level !== "error", findings: [f] }) }
        })
        return lines.filter(function (l) { return !l.met }).concat(lines.filter(function (l) { return l.met }))
    }
    function errorCount(rep) {
        return rep ? (rep.errors || 0) + (rep === report ? unanswered.length : 0) : 0
    }

    // A slug of the name: lowercase letters, digits and hyphens, starting with a letter, at most 32 (the scaffold's id).
    function slug(t) {
        var s = t.toLowerCase()
        try { s = s.normalize("NFKD").replace(/[̀-ͯ]/g, "") } catch (e) {}
        s = s.replace(/[^a-z0-9]+/g, "-").replace(/^[^a-z]+/, "")
        return s.slice(0, 32).replace(/-+$/, "")
    }
    function setName(t) {
        name = t
        if (!idTouched) modId = slug(t)
    }
    function pickStart(v) {
        if (locked) return
        starts = v
        parts = ({ module: ["widget", "peek", "panel"], panel: ["panel"], desk: ["desk"], command: [], blank: [] })[v]
        runsOn = v === "command" ? "host" : "views"
    }
    function togglePart(part) {
        if (locked) return
        var i = parts.indexOf(part)
        var next = parts.slice()
        if (i >= 0) next.splice(i, 1); else next.push(part)
        parts = next
    }
    function setReason(point, t) {
        var r = Object.assign({}, reasons)
        r[point] = t
        reasons = r
    }
    function useIndex(kind, id) {
        for (var i = 0; i < uses.length; i++) if (uses[i].kind === kind && uses[i].id === id) return i
        return -1
    }
    function toggleUse(kind, id) {
        if (locked) return
        var next = uses.slice(), i = useIndex(kind, id)
        if (i >= 0) next.splice(i, 1); else next.push({ kind: kind, id: id, optional: false })
        uses = next
    }
    function setOptional(kind, id, on) {
        var i = useIndex(kind, id)
        if (i < 0 || locked) return
        var next = uses.slice()
        next[i] = { kind: kind, id: id, optional: on }
        uses = next
    }

    // The documents a mod may read (MODS.md "uses"): the shell's services. The actions are the daemon's registry.
    readonly property var docIds: ["svc.media", "svc.clock", "svc.audio", "svc.notifications", "svc.power", "svc.network",
                                   "svc.bluetooth", "svc.brightness", "svc.workspaces", "svc.tray"]
    readonly property var candidates: {
        var c = docIds.map(function (d) { return { kind: "doc", id: d, help: "" } })
        return c.concat(actions.map(function (a) { return { kind: "action", id: a.id, help: a.help || "" } }))
    }
    // What the list shows: the chosen entries, then up to eight that match the search.
    readonly property var usesShown: {
        var q = usesQuery.trim().toLowerCase()
        var chosen = [], rest = []
        for (var i = 0; i < candidates.length; i++) {
            var c = candidates[i]
            if (useIndex(c.kind, c.id) >= 0) chosen.push(c)
            else if (rest.length < 8 && (q === "" || c.id.toLowerCase().indexOf(q) >= 0 || c.help.toLowerCase().indexOf(q) >= 0))
                rest.push(c)
        }
        return chosen.concat(rest)
    }

    // --- requests -----------------------------------------------------------------------------------
    function refreshLists() {
        if (!Store.live) return
        Store.query("points", "", function (items) { if (items) p.points = items })
        Store.query("actions", "", function (items) { p.actions = items || [] })
    }
    // One `mod.check {spec}` per ~250 ms of quiet (a one-shot timer: it runs only after a change, never at rest). A
    // check changes nothing, so it goes as a plain request: Store.act would count it as a change that went through.
    Timer {
        id: debounce
        interval: 250
        onTriggered: p.runCheck()
    }
    function runCheck() {
        if (locked || !Store.live) return
        if (name.trim() === "" && modId === "") { report = null; refusal = ""; checking = false; return }
        var n = ++checkSeq
        checking = true
        Store.request({ t: "act", action: "mod.check", args: { spec: spec } }, function (m) {
            if (n !== p.checkSeq) return
            p.checking = false
            if (m.t === "done") {
                p.report = m.data || null
                p.refusal = ""
                if (p.files.every(function (f) { return f.path !== p.openFile })) p.openFile = ""
            } else {
                p.report = null
                p.refusal = m.msg && I18n.has(m.msg) ? m.msg : Store.actError(m, "settings.err.unknown_action")
            }
        })
    }
    function refusalText(key) { return I18n.has(key) ? I18n.tr(key) : key }
    // The folder mod.new writes into (PROTOCOL §6): named by the write error, whose key carries no path.
    function folderOf(id) {
        var data = Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
        return data + "/kurashi/mods/" + id
    }
    readonly property bool idError: refusal === "mods.new.error.id_invalid" || refusal === "mods.new.error.id_taken"
    // Why Create is inert, or "" when it is not.
    readonly property string createReason: {
        if (!Store.live) return I18n.tr("mods.new.create.daemon_away")
        if (name.trim() === "") return I18n.tr("mods.new.create.needs_name")
        if (refusal !== "") return refusalText(refusal)
        if (report === null) return ""
        var n = errorCount(report)
        if (n > 0) return n === 1 ? I18n.tr("mods.new.check.failed_one") : I18n.fmt("mods.new.check.failed", { n: n })
        return ""
    }
    readonly property bool canCreate: createReason === "" && report !== null && !checking && !creating && !locked
    function create() {
        if (!canCreate) return
        var s = spec
        creating = true
        createError = ""
        Store.act("mod.new", { spec: s }, function (m) {
            p.creating = false
            if (m.t === "done") {
                var d = m.data || ({})
                p.created = { id: s.id, path: d.path || p.folderOf(s.id), check: d.check || null }
                Qt.callLater(function () { turnOnBtn.forceActiveFocus(); p.reveal(createdBox) })
            } else if (m.msg === "mods.new.error.write") {
                p.createError = I18n.fmt("mods.new.error.write", { path: p.folderOf(s.id) })
            } else {
                p.createError = m.msg && I18n.has(m.msg) ? I18n.tr(m.msg) : Store.actError(m, "settings.err.unknown_action")
            }
        })
    }
    // The new mod as the daemon's `mods` document has it, read live.
    readonly property var createdEntry: created ? (Store.modEntry(created.id) || null) : null
    readonly property string forcedOn: Store.forcedReason("mods.loaded") || Store.forcedReason("mods.enabled")
    readonly property bool hasPage: {
        if (!created) return false
        var ps = Store.schema.pages || []
        return ps.some(function (x) { return x.id === "mods." + p.created.id })
    }
    // Turn it on: `mod.load` (its page joins Settings), then `mod.enable`. Nothing is enabled without this click.
    function turnOn() {
        if (!created || turning || forcedOn !== "") return
        var id = created.id
        var enable = function () {
            Store.act("mod.enable", { id: id }, function (m) {
                p.turning = false
                if (m.t !== "done") p.turnError = Store.actError(m, "settings.err.unknown_action")
            })
        }
        turning = true
        turnError = ""
        if (createdEntry && createdEntry.state === "disabled") { enable(); return }
        Store.act("mod.load", { id: id }, function (m) {
            if (m.t === "done") { enable(); return }
            p.turning = false
            p.turnError = Store.actError(m, "settings.err.unknown_action")
        })
    }

    // Esc: back to the Mods page; a form with input asks first (UX brief, Keyboard).
    function goBack() {
        if (asking) { asking = false; nameField.focusInput(); return }
        if (typed && !locked) { asking = true; Qt.callLater(function () { keepBtn.forceActiveFocus() }); return }
        leave()
    }
    Keys.onEscapePressed: event => { p.goBack(); event.accepted = true }

    // Scrolls the least that brings the item into view.
    function reveal(item) {
        var top = item.mapToItem(p.contentItem, 0, 0).y
        var bottom = top + item.height
        if (top < p.contentY) p.contentY = Math.max(0, top - Theme.pad)
        else if (bottom > p.contentY + p.height) p.contentY = Math.min(bottom - p.height + Theme.pad, p.contentHeight - p.height)
    }
    // The keyboard focus follows into view (a long form scrolls under it).
    Connections {
        target: p.Window.window
        function onActiveFocusItemChanged() {
            var f = p.Window.window ? p.Window.window.activeFocusItem : null
            for (var it = f; it; it = it.parent) if (it === p) { p.reveal(f); return }
        }
    }

    // The test hook's view of the page (the suite reads it; shell.qml `modNew`).
    function state() {
        return JSON.stringify({ name: name, id: modId, parts: spec.with, host: spec.host || "", uses: spec.uses,
                                refusal: refusal, idError: idError, checking: checking,
                                passed: report ? report.passed === true && errorCount(report) === 0 : null,
                                errors: errorCount(report), files: files.map(function (f) { return f.path }),
                                openFile: openFile, createReason: createReason, createError: createError,
                                created: created ? created.path : "", modState: createdEntry ? createdEntry.state : "",
                                hasPage: hasPage, forcedOn: forcedOn, asking: asking, points: points.length,
                                actions: actions.length, unanswered: unanswered })
    }

    Component.onCompleted: { refreshLists(); Qt.callLater(function () { nameField.focusInput() }) }
    Connections {
        target: Store
        function onLiveChanged() {
            if (Store.live) { p.refreshLists(); debounce.restart() }
            else { p.report = null; p.checking = false }
        }
    }

    contentWidth: width
    contentHeight: col.implicitHeight + Theme.pad * 2 + (asking ? askBar.height : 0)
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // --- the page's own small parts (one place, K153) -------------------------------------------------
    // A line under a control: dim, a size down.
    component Hint: Label {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        dim: true
        font.pixelSize: Theme.fs - 2
    }
    // What is wrong, under the control it is about (role and glyph, not colour alone).
    component Problem: Label {
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs - 2
        Accessible.role: Accessible.AlertMessage
        Accessible.name: text
    }
    // A field's name above it.
    component Head: Label {
        topPadding: Theme.gap / 2
        font.weight: Theme.wMedium
    }
    // A row of a list that moves with the arrows (one Tab stop per list): a focus ring, Space and Return act.
    component Pickable: Item {
        id: pk
        property bool on: false
        property bool tabStop: false
        signal acted()
        signal moved(int by)
        activeFocusOnTab: tabStop
        Keys.onSpacePressed: event => { pk.acted(); event.accepted = true }
        Keys.onReturnPressed: event => { pk.acted(); event.accepted = true }
        Keys.onUpPressed: event => { pk.moved(-1); event.accepted = true }
        Keys.onDownPressed: event => { pk.moved(1); event.accepted = true }
        Keys.onLeftPressed: event => { pk.moved(-1); event.accepted = true }
        Keys.onRightPressed: event => { pk.moved(1); event.accepted = true }
        TapHandler { onTapped: { pk.forceActiveFocus(); pk.acted() } }
        FocusRing { z: 10; anchors.fill: parent; anchors.margins: -2; shown: pk.activeFocus; corner: Theme.rSm }
    }
    // Moves the focus to the neighbour in a Repeater's list of Pickables (`item` finds the Pickable of a delegate).
    function step(rep, from, by, item) {
        var n = rep.count
        if (n === 0) return from
        var to = Math.max(0, Math.min(n - 1, from + by))
        var it = rep.itemAt(to)
        if (it) (item ? item(it) : it).forceActiveFocus()
        return to
    }

    Column {
        id: col
        x: Theme.pad
        y: Theme.pad
        spacing: Theme.pad
        width: p.width - 2 * Theme.pad

        Row {
            spacing: Theme.gap / 2
            LinkText {
                objectName: "mod-new-back"
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("settings.ui.mods")
                onActivated: p.goBack()
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                dim: true
                font.pixelSize: Theme.fs - 2
                text: "›"
            }
        }
        PageHeader {
            width: parent.width
            text: I18n.tr("mods.new.title")
        }
        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            dim: true
            text: I18n.tr("mods.new.intro")
        }

        // Two columns when the page is wide (form left, result right), one below the other when narrow.
        Item {
            id: cols
            readonly property bool wide: width >= 740
            width: parent.width
            height: wide ? Math.max(form.height, result.height) : form.height + Theme.pad + result.height

            Column {
                id: form
                width: cols.wide ? Math.floor((cols.width - Theme.pad) * 0.56) : cols.width
                spacing: Theme.pad
                enabled: !p.locked
                opacity: p.locked ? 0.6 : 1

                // 1. What it is.
                SectionCard {
                    width: form.width
                    title: I18n.tr("mods.new.group.what")
                    icon: "label"
                    Column {
                        width: parent.width
                        spacing: Theme.gap / 2
                        Head { text: I18n.tr("mods.new.name") }
                        TextField {
                            id: nameField
                            objectName: "mod-new-name"
                            width: parent.width
                            label: I18n.tr("mods.new.name")
                            placeholder: I18n.tr("mods.new.name.hint")
                            value: p.name
                            invalid: p.refusal === "mods.new.error.name_empty" && p.modId !== ""
                            onTyping: t => p.setName(t)
                        }
                        Problem {
                            visible: nameField.invalid
                            text: "✕ " + I18n.tr("mods.new.error.name_empty")
                        }
                        Head { text: I18n.tr("mods.new.id") }
                        TextField {
                            id: idField
                            objectName: "mod-new-id"
                            width: parent.width
                            mono: true
                            label: I18n.tr("mods.new.id")
                            value: p.modId
                            invalid: p.idError
                            // (emptied, it follows the name again from its next edit)
                            onTyping: t => { p.idTouched = t !== ""; p.modId = t }
                        }
                        Problem {
                            objectName: "mod-new-id-error"
                            visible: p.idError
                            text: "✕ " + (p.idError ? I18n.tr(p.refusal) : "")
                        }
                        Hint { text: I18n.tr("mods.new.id.help") }
                        Head { text: I18n.tr("mods.new.icon") }
                        Row {
                            width: parent.width
                            spacing: Theme.gap
                            Rectangle {
                                width: Theme.controlH
                                height: Theme.controlH
                                radius: Theme.rSm
                                color: Theme.surface
                                border.width: 1
                                border.color: Theme.outline
                                Icon {
                                    anchors.centerIn: parent
                                    name: p.icon.trim()
                                    size: Theme.fs + 8
                                    color: Theme.accent
                                }
                            }
                            TextField {
                                objectName: "mod-new-icon"
                                width: parent.width - Theme.controlH - Theme.gap
                                mono: true
                                label: I18n.tr("mods.new.icon")
                                placeholder: I18n.tr("mods.new.icon.search")
                                value: p.icon
                                invalid: p.refusal === "mods.new.error.icon_invalid"
                                onTyping: t => p.icon = t
                            }
                        }
                        Problem {
                            visible: p.refusal === "mods.new.error.icon_invalid"
                            text: "✕ " + I18n.tr("mods.new.error.icon_invalid")
                        }
                        Head { text: I18n.tr("mods.new.description") }
                        TextField {
                            objectName: "mod-new-description"
                            width: parent.width
                            label: I18n.tr("mods.new.description")
                            placeholder: I18n.tr("mods.new.description.hint")
                            value: p.description
                            onTyping: t => p.description = t
                        }
                    }
                }

                // 2. Starts as: one card; it presets group 3 (a start, every tick can change).
                SectionCard {
                    width: form.width
                    title: I18n.tr("mods.new.group.starts")
                    icon: "category"
                    Flow {
                        id: startFlow
                        width: parent.width
                        spacing: Theme.gap
                        Accessible.role: Accessible.Grouping
                        Accessible.name: I18n.tr("mods.new.group.starts")
                        readonly property var choices: [
                            { v: "module", icon: "toolbar" }, { v: "panel", icon: "right_panel_open" },
                            { v: "desk", icon: "desk" }, { v: "command", icon: "terminal" }, { v: "blank", icon: "draft" }]
                        readonly property real cardW: Math.max(120, Math.floor((width - 2 * Theme.gap) / 3))
                        Repeater {
                            id: startRep
                            model: startFlow.choices
                            delegate: Pickable {
                                id: card
                                required property var modelData
                                required property int index
                                objectName: "mod-new-start:" + modelData.v
                                on: p.starts === modelData.v
                                tabStop: on
                                width: startFlow.cardW
                                height: cardCol.implicitHeight + 2 * Theme.gap
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: I18n.tr("mods.new.starts." + modelData.v)
                                Accessible.description: I18n.tr("mods.new.starts." + modelData.v + ".about")
                                Accessible.checked: on
                                onActed: p.pickStart(modelData.v)
                                // Arrows pick as they move, as a radio group does.
                                onMoved: by => {
                                    var to = Math.max(0, Math.min(startFlow.choices.length - 1, card.index + by))
                                    p.pickStart(startFlow.choices[to].v)
                                    p.step(startRep, card.index, by)
                                }
                                // (the picked card: the accent's edge and the label's weight, not colour alone)
                                Rectangle {
                                    anchors.fill: parent
                                    border.width: card.on ? 2 : 1
                                    border.color: card.on ? Theme.accent : Theme.outline
                                    radius: Theme.rSm
                                    color: Theme.surface
                                }
                                Column {
                                    id: cardCol
                                    x: Theme.gap
                                    y: Theme.gap
                                    width: parent.width - 2 * Theme.gap
                                    spacing: 2
                                    Icon {
                                        name: card.modelData.icon
                                        size: Theme.fs + 6
                                        color: card.on ? Theme.accent : Theme.dim
                                        filled: card.on
                                    }
                                    Label {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        font.weight: card.on ? Theme.wMedium : Theme.wRegular
                                        text: I18n.tr("mods.new.starts." + card.modelData.v)
                                    }
                                    Hint { text: I18n.tr("mods.new.starts." + card.modelData.v + ".about") }
                                }
                            }
                        }
                    }
                }

                // 3. Where it shows: the checklist, from the points registry.
                SectionCard {
                    width: form.width
                    title: I18n.tr("mods.new.group.where")
                    icon: "place"
                    Column {
                        id: whereCol
                        width: parent.width
                        spacing: Theme.gap / 2
                        property int at: 0
                        Hint { text: I18n.tr("mods.new.where.help"); bottomPadding: Theme.gap / 2 }
                        Hint {
                            visible: p.partRows.length === 0
                            text: Store.live ? "…" : I18n.tr("mods.new.create.daemon_away")
                        }
                        Repeater {
                            id: whereRep
                            model: p.partRows
                            delegate: Column {
                                id: wr
                                required property var modelData
                                required property int index
                                readonly property bool ticked: p.parts.indexOf(modelData.part) >= 0
                                readonly property bool asks: p.needsReason(modelData)
                                readonly property bool empty: p.unanswered.indexOf(modelData.point) >= 0
                                width: whereCol.width
                                spacing: 2
                                Pickable {
                                    id: tick
                                    objectName: "mod-new-part:" + wr.modelData.part
                                    width: parent.width
                                    height: Math.max(Theme.controlH - 6, tickLabel.implicitHeight + 6)
                                    on: wr.ticked
                                    tabStop: wr.index === whereCol.at
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: I18n.tr("mods.new.part." + wr.modelData.part)
                                    Accessible.checkable: true
                                    Accessible.checked: wr.ticked
                                    onActed: { whereCol.at = wr.index; p.togglePart(wr.modelData.part) }
                                    onMoved: by => whereCol.at = p.step(whereRep, wr.index, by, function (d) { return d.children[0] })
                                    onActiveFocusChanged: if (activeFocus) whereCol.at = wr.index
                                    Icon {
                                        id: box
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: wr.ticked ? "check_box" : "check_box_outline_blank"
                                        filled: wr.ticked
                                        size: Theme.fs + 4
                                        color: wr.ticked ? Theme.accent : Theme.dim
                                    }
                                    Label {
                                        id: tickLabel
                                        anchors.left: box.right
                                        anchors.leftMargin: Theme.gap
                                        anchors.right: fill.left
                                        anchors.rightMargin: Theme.gap
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        text: I18n.tr("mods.new.part." + wr.modelData.part)
                                    }
                                    Label {
                                        id: fill
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, parent.width * 0.45)
                                        elide: Text.ElideRight
                                        dim: true
                                        font.family: "monospace"
                                        font.pixelSize: Theme.fs - 3
                                        text: wr.modelData.fill
                                    }
                                }
                                // An expected variant left out says why in a line ([skips]); the template's line to accept.
                                Column {
                                    visible: wr.asks
                                    x: Theme.fs + 4 + Theme.gap
                                    width: parent.width - x
                                    spacing: 2
                                    bottomPadding: Theme.gap / 2
                                    TextField {
                                        objectName: "mod-new-skip:" + wr.modelData.point
                                        width: parent.width
                                        label: I18n.tr("mods.new.skip.reason") + ": " + I18n.tr("mods.new.part." + wr.modelData.part)
                                        // (before the first draft: the suggestion to accept)
                                        placeholder: I18n.tr("mods.new.skip.suggest")
                                        value: p.reasonOf(wr.modelData.point)
                                        invalid: wr.empty
                                        onTyping: t => p.setReason(wr.modelData.point, t)
                                    }
                                    Problem {
                                        visible: wr.empty
                                        text: "✕ " + I18n.tr("mods.check.variant")
                                    }
                                    Hint {
                                        visible: !wr.empty && p.reasons[wr.modelData.point] !== undefined
                                                 && p.reasons[wr.modelData.point] !== (p.templateSkips[wr.modelData.point] || "")
                                        text: I18n.tr("mods.new.skip.template")
                                    }
                                }
                            }
                        }
                        Problem {
                            visible: p.refusal === "mods.new.error.nothing_chosen" || p.refusal.indexOf("mods.new.error.part_unknown") === 0
                            text: "✕ " + p.refusalText(p.refusal)
                        }
                    }
                }

                // 4. What it uses, then Runs on.
                SectionCard {
                    width: form.width
                    title: I18n.tr("mods.new.group.uses")
                    icon: "join"
                    Column {
                        id: usesCol
                        width: parent.width
                        spacing: Theme.gap / 2
                        property int at: 0
                        Hint { text: I18n.tr("mods.new.uses.help"); bottomPadding: Theme.gap / 2 }
                        TextField {
                            objectName: "mod-new-uses-search"
                            width: parent.width
                            enabled: Store.live
                            label: I18n.tr("mods.new.uses.search")
                            placeholder: I18n.tr("mods.new.uses.search")
                            value: p.usesQuery
                            onTyping: t => { p.usesQuery = t; usesCol.at = 0 }
                        }
                        Hint {
                            visible: !Store.live
                            text: "⊘ " + I18n.tr("mods.new.create.daemon_away")
                        }
                        Hint {
                            visible: Store.live && p.uses.length === 0
                            text: I18n.tr("mods.new.uses.none")
                        }
                        Repeater {
                            id: usesRep
                            model: Store.live ? p.usesShown : []
                            delegate: Item {
                                id: ur
                                required property var modelData
                                required property int index
                                readonly property bool chosen: p.useIndex(modelData.kind, modelData.id) >= 0
                                readonly property bool optional: chosen && p.uses[p.useIndex(modelData.kind, modelData.id)].optional
                                width: usesCol.width
                                height: Math.max(Theme.controlH - 6, useText.implicitHeight + 6)
                                Pickable {
                                    id: usePick
                                    objectName: "mod-new-use:" + ur.modelData.kind + ":" + ur.modelData.id
                                    anchors.left: parent.left
                                    anchors.right: optBox.left
                                    anchors.rightMargin: Theme.gap
                                    height: parent.height
                                    on: ur.chosen
                                    tabStop: ur.index === usesCol.at
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: ur.modelData.id
                                    Accessible.description: ur.modelData.help
                                    Accessible.checkable: true
                                    Accessible.checked: ur.chosen
                                    onActed: { usesCol.at = ur.index; p.toggleUse(ur.modelData.kind, ur.modelData.id) }
                                    onMoved: by => usesCol.at = p.step(usesRep, ur.index, by, function (d) { return d.children[0] })
                                    onActiveFocusChanged: if (activeFocus) usesCol.at = ur.index
                                    Icon {
                                        id: useBox
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: ur.chosen ? "check_box" : "check_box_outline_blank"
                                        filled: ur.chosen
                                        size: Theme.fs + 4
                                        color: ur.chosen ? Theme.accent : Theme.dim
                                    }
                                    Column {
                                        id: useText
                                        anchors.left: useBox.right
                                        anchors.leftMargin: Theme.gap
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        Label {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            font.family: "monospace"
                                            font.pixelSize: Theme.fs - 1
                                            text: ur.modelData.kind + ":" + ur.modelData.id
                                        }
                                        Hint {
                                            visible: text !== ""
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            text: ur.modelData.help
                                        }
                                    }
                                }
                                // Required, or "works without it" (`?`).
                                Row {
                                    id: optBox
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.gap / 2
                                    visible: ur.chosen
                                    width: ur.chosen ? implicitWidth : 0
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        dim: true
                                        font.pixelSize: Theme.fs - 2
                                        text: I18n.tr("mods.new.uses.optional")
                                    }
                                    Toggle {
                                        objectName: "mod-new-optional:" + ur.modelData.id
                                        anchors.verticalCenter: parent.verticalCenter
                                        label: I18n.tr("mods.new.uses.optional") + ": " + ur.modelData.id
                                        checked: ur.optional
                                        onToggled: v => p.setOptional(ur.modelData.kind, ur.modelData.id, v)
                                    }
                                }
                            }
                        }

                        Head { text: I18n.tr("mods.new.runs"); topPadding: Theme.gap }
                        Column {
                            id: runsCol
                            width: parent.width
                            spacing: 2
                            Accessible.role: Accessible.Grouping
                            Accessible.name: I18n.tr("mods.new.runs")
                            // The two inert ones say why (the shell's tree: a checkout only; Luau: with portable mods).
                            readonly property var choices: [
                                { v: "views", inert: "" }, { v: "host", inert: "" },
                                { v: "tree", inert: "mods.new.runs.tree.inert" }, { v: "luau", inert: "mods.new.runs.luau.about" }]
                            readonly property var live: choices.filter(function (c) { return c.inert === "" })
                            Repeater {
                                id: runsRep
                                model: runsCol.choices
                                delegate: Pickable {
                                    id: run
                                    required property var modelData
                                    required property int index
                                    readonly property bool inert: modelData.inert !== ""
                                    objectName: "mod-new-runs:" + modelData.v
                                    on: p.runsOn === modelData.v
                                    tabStop: on
                                    width: runsCol.width
                                    height: runText.implicitHeight + Theme.gap
                                    opacity: inert ? 0.55 : 1
                                    Accessible.role: Accessible.RadioButton
                                    Accessible.name: I18n.tr("mods.new.runs." + modelData.v)
                                    Accessible.description: inert ? I18n.tr(modelData.inert) : I18n.tr("mods.new.runs." + modelData.v + ".about")
                                    Accessible.checked: on
                                    onActed: if (!inert && !p.locked) p.runsOn = modelData.v
                                    // The arrows move between the ones that can be picked, and pick.
                                    onMoved: by => {
                                        var l = runsCol.live
                                        var i = l.findIndex(function (c) { return c.v === p.runsOn })
                                        var to = Math.max(0, Math.min(l.length - 1, i + by))
                                        if (p.locked) return
                                        p.runsOn = l[to].v
                                        runsRep.itemAt(runsCol.choices.findIndex(function (c) { return c.v === l[to].v })).forceActiveFocus()
                                    }
                                    Icon {
                                        id: radio
                                        y: 2
                                        name: run.on ? "check_circle" : "radio_button_unchecked"
                                        filled: run.on
                                        size: Theme.fs + 4
                                        color: run.on ? Theme.accent : Theme.dim
                                    }
                                    Column {
                                        id: runText
                                        anchors.left: radio.right
                                        anchors.leftMargin: Theme.gap
                                        anchors.right: parent.right
                                        Label {
                                            width: parent.width
                                            wrapMode: Text.WordWrap
                                            text: I18n.tr("mods.new.runs." + run.modelData.v)
                                        }
                                        Hint {
                                            text: run.inert ? "⊘ " + I18n.tr(run.modelData.inert)
                                                            : I18n.tr("mods.new.runs." + run.modelData.v + ".about")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // --- the result: Files, Check, Create ---------------------------------------------------------
            Column {
                id: result
                x: cols.wide ? form.width + Theme.pad : 0
                y: cols.wide ? 0 : form.height + Theme.pad
                width: cols.wide ? cols.width - form.width - Theme.pad : cols.width
                spacing: Theme.pad

                // Created: the three follow-ups and the check's report on the written files.
                SectionCard {
                    id: createdBox
                    visible: p.locked
                    width: result.width
                    title: I18n.tr("mods.new.create")
                    icon: "check_circle"
                    Column {
                        width: parent.width
                        spacing: Theme.gap
                        Label {
                            objectName: "mod-new-created"
                            width: parent.width
                            wrapMode: Text.WrapAnywhere
                            text: p.created ? I18n.fmt("mods.new.created", { path: p.created.path }) : ""
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }
                        Row {
                            visible: !!p.createdEntry
                            spacing: Theme.gap
                            Chip {
                                text: p.createdEntry ? I18n.tr("settings.ui.mod_state." + p.createdEntry.state) : ""
                                fg: p.createdEntry && p.createdEntry.state === "enabled" ? Theme.fg : Theme.dim
                            }
                        }
                        Flow {
                            width: parent.width
                            spacing: Theme.gap
                            Button {
                                id: turnOnBtn
                                objectName: "mod-new-turn-on"
                                primary: true
                                label: I18n.tr("mods.new.turn_on")
                                enabled: Store.live && p.forcedOn === "" && !p.turning
                                         && !(p.createdEntry && p.createdEntry.state === "enabled")
                                onClicked: p.turnOn()
                            }
                            Button {
                                objectName: "mod-new-open-page"
                                label: I18n.tr("mods.new.open_page")
                                enabled: p.hasPage
                                onClicked: p.pageRequested("mod:" + p.created.id)
                            }
                        }
                        Hint {
                            visible: p.forcedOn !== ""
                            text: "⊘ " + p.forcedOn
                        }
                        Hint {
                            visible: !p.hasPage && p.forcedOn === ""
                            text: I18n.tr("mods.new.open_page.needs_on")
                        }
                        Problem {
                            visible: p.turnError !== ""
                            text: "✕ " + p.turnError
                        }
                    }
                }

                SectionCard {
                    width: result.width
                    title: I18n.tr("mods.new.files")
                    icon: "folder"
                    visible: !p.locked
                    Column {
                        id: filesCol
                        width: parent.width
                        spacing: 2
                        property int at: 0
                        Hint {
                            visible: p.files.length === 0
                            text: p.refusal !== "" ? "✕ " + p.refusalText(p.refusal)
                                : !Store.live ? "⊘ " + I18n.tr("mods.new.create.daemon_away")
                                : I18n.tr("mods.new.files.none")
                        }
                        Repeater {
                            id: filesRep
                            model: p.files
                            delegate: Pickable {
                                id: fr
                                required property var modelData
                                required property int index
                                objectName: "mod-new-file:" + modelData.path
                                on: p.openFile === modelData.path
                                tabStop: index === Math.min(filesCol.at, p.files.length - 1)
                                width: filesCol.width
                                height: Theme.controlH - 8
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.path
                                Accessible.checked: on
                                onActed: {
                                    filesCol.at = index
                                    p.openFile = on ? "" : modelData.path
                                    if (p.openFile !== "") Qt.callLater(function () { p.reveal(preview) })
                                }
                                onMoved: by => filesCol.at = p.step(filesRep, fr.index, by)
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.rSm
                                    color: fr.on ? Theme.containerHigh : "transparent"
                                }
                                Icon {
                                    id: fileIcon
                                    x: Theme.gap / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: fr.modelData.path === "mod.toml" ? "description" : "draft"
                                    size: Theme.fs + 2
                                    color: Theme.dim
                                }
                                Label {
                                    anchors.left: fileIcon.right
                                    anchors.leftMargin: Theme.gap
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideMiddle
                                    font.family: "monospace"
                                    font.pixelSize: Theme.fs - 1
                                    text: fr.modelData.path
                                }
                            }
                        }
                        // The open file, read-only.
                        Rectangle {
                            id: preview
                            objectName: "mod-new-preview"
                            readonly property var file: p.files.find(function (f) { return f.path === p.openFile }) || null
                            visible: file !== null
                            width: parent.width
                            height: previewText.implicitHeight + 2 * Theme.gap
                            radius: Theme.rSm
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.outline
                            Accessible.role: Accessible.StaticText
                            Accessible.name: file ? file.path : ""
                            Label {
                                id: previewText
                                x: Theme.gap
                                y: Theme.gap
                                width: parent.width - 2 * Theme.gap
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                font.family: "monospace"
                                font.pixelSize: Theme.fs - 3
                                text: parent.file ? parent.file.text : ""
                            }
                        }
                    }
                }

                SectionCard {
                    id: checkCard
                    width: result.width
                    title: I18n.tr("mods.new.check")
                    icon: "checklist"
                    readonly property var rep: p.locked ? (p.created.check || null) : p.report
                    readonly property var lines: p.ruleLines(rep)
                    visible: rep !== null
                    Column {
                        width: parent.width
                        spacing: Theme.gap / 2
                        Label {
                            objectName: "mod-new-check-summary"
                            width: parent.width
                            wrapMode: Text.WordWrap
                            font.weight: Theme.wMedium
                            readonly property int n: p.errorCount(checkCard.rep)
                            text: !checkCard.rep ? ""
                                : (n === 0 ? I18n.tr("mods.new.check.passed")
                                   : n === 1 ? I18n.tr("mods.new.check.failed_one") : I18n.fmt("mods.new.check.failed", { n: n }))
                                  + ((checkCard.rep.notes || 0) === 1 ? " · " + I18n.tr("mods.new.check.notes_one")
                                     : (checkCard.rep.notes || 0) > 1 ? " · " + I18n.fmt("mods.new.check.notes", { n: checkCard.rep.notes }) : "")
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                        }
                        // One line per rule: met or not, with what to change (a list with role and state, not colour alone).
                        Column {
                            width: parent.width
                            spacing: 2
                            Accessible.role: Accessible.List
                            Accessible.name: I18n.tr("mods.new.check")
                            Repeater {
                                model: checkCard.lines
                                delegate: Item {
                                    id: line
                                    required property var modelData
                                    width: parent.width
                                    height: lineCol.implicitHeight + 4
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: lineLabel.text + ", " + I18n.tr(modelData.met ? "mods.new.check.met" : "mods.new.check.not_met")
                                    Icon {
                                        id: mark
                                        y: 1
                                        name: line.modelData.met ? "check_circle" : "error"
                                        filled: !line.modelData.met
                                        size: Theme.fs + 1
                                        color: line.modelData.met ? Theme.dim : Theme.error
                                    }
                                    Column {
                                        id: lineCol
                                        anchors.left: mark.right
                                        anchors.leftMargin: Theme.gap
                                        anchors.right: parent.right
                                        Label {
                                            id: lineLabel
                                            width: parent.width
                                            wrapMode: Text.WordWrap
                                            color: line.modelData.met ? Theme.dim : Theme.fg
                                            font.pixelSize: Theme.fs - 1
                                            // (a met line says so by its mark and its name; a line not met in words too)
                                            text: (I18n.has("mods.check." + line.modelData.rule) ? I18n.tr("mods.check." + line.modelData.rule)
                                                   : line.modelData.rule)
                                                  + (line.modelData.met ? "" : " · " + I18n.tr("mods.new.check.not_met"))
                                        }
                                        Repeater {
                                            model: line.modelData.findings
                                            Hint {
                                                required property var modelData
                                                color: modelData.level === "error" ? Theme.error : Theme.dim
                                                text: (modelData.level === "error" ? "✕ " : "· ") + modelData.at + " — " + modelData.detail
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SectionCard {
                    width: result.width
                    visible: !p.locked
                    title: I18n.tr("mods.new.create")
                    icon: "add"
                    Column {
                        width: parent.width
                        spacing: Theme.gap / 2
                        // Where it goes (nothing while there is no id: the reason under the button says what is missing).
                        Hint { visible: p.modId !== ""; text: p.folderOf(p.modId); wrapMode: Text.WrapAnywhere }
                        Button {
                            objectName: "mod-new-create"
                            primary: true
                            label: I18n.tr("mods.new.create")
                            enabled: p.canCreate
                            onClicked: p.create()
                        }
                        Hint {
                            objectName: "mod-new-create-reason"
                            visible: p.createReason !== ""
                            text: "⊘ " + p.createReason
                        }
                        Problem {
                            objectName: "mod-new-create-error"
                            visible: p.createError !== ""
                            text: "✕ " + p.createError
                        }
                    }
                }
            }
        }
    }

    // "Discard this mod?" — at the page's foot, over the content (Esc on a form with input).
    Rectangle {
        id: askBar
        parent: p
        visible: p.asking
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.pad
        height: askRow.implicitHeight + 2 * Theme.gap
        radius: Theme.rLg
        color: Theme.containerHigh
        border.width: 1
        border.color: Theme.outline
        Accessible.role: Accessible.AlertMessage
        Accessible.name: I18n.tr("mods.new.discard")
        Row {
            id: askRow
            x: Theme.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("mods.new.discard")
            }
            Button {
                id: keepBtn
                objectName: "mod-new-keep"
                label: I18n.tr("mods.new.discard.keep")
                onClicked: p.goBack()
            }
            Button {
                objectName: "mod-new-discard"
                primary: true
                label: I18n.tr("mods.new.discard.leave")
                onClicked: { p.asking = false; p.leave() }
            }
        }
    }
}
