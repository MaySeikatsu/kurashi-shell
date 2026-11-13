import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.components.decor

// The "Open in…" step (`surface:chooser`; docs/ux/sessions.md "The flow" 2): where the chosen session opens — in the
// shell's terminal (the terminal mod's drop-down), the default terminal window, or another installed terminal — with
// "Remember for this project" and, when the project has a desk, "Restore the desk too". Drawn as a card apart with the
// launcher's rows; on the output the request named, else the focused one. Unmapped while no step is shown here: 0 frames.
//
// The first screen's instance also sends the daemon's handoffs: actions of other mods (terminal.run, terminal.open_dir,
// webdock.open, settings.open) that a native mod cannot invoke itself yet (CONTRACT-CHANGE 810), and answers `collect`
// with the other mods' parts of a desk just saved.
PanelWindow {
    id: ch
    required property var screen

    Watch { doc: "mod.sessions" }
    Watch { doc: "svc.workspaces"; active: ch.asking }
    Watch { doc: "mods"; active: ch.asking || ch.firstHere }
    Watch { doc: "mod.terminal"; active: ch.collecting && ch.modOn("terminal") }
    Watch { doc: "mod.webdock"; active: ch.collecting && ch.modOn("webdock") }

    readonly property var d: Store.docs["mod.sessions"] || ({})
    readonly property var c: d.choosing || null
    readonly property bool asking: c !== null
    readonly property string outName: screen ? screen.name : ""
    readonly property bool firstHere: Quickshell.screens.length > 0 && Quickshell.screens[0].name === outName
    function modOn(id) {
        var m = (Store.docs["mods"] || {}).mods || []
        for (var i = 0; i < m.length; i++) if (m[i].id === id) return m[i].state === "enabled"
        return false
    }
    function focusedHere() {
        var o = (Store.docs["svc.workspaces"] && Store.docs["svc.workspaces"].outputs) || {}
        var any = false
        for (var n in o) {
            var l = o[n] || []
            for (var j = 0; j < l.length; j++) if (l[j].focused) { any = true; if (n === outName) return true }
        }
        return !any && firstHere
    }
    readonly property bool want: asking && (c.output !== undefined ? c.output === outName : focusedHere())

    // ---- handoffs (first screen only) ----
    readonly property var handoffs: firstHere ? (d.handoff || []) : []
    readonly property bool pending: handoffs.length > 0
    property real sentUpTo: 0
    onHandoffsChanged: Qt.callLater(sendHandoffs)
    readonly property var modsDoc: Store.docs["mods"]
    onModsDocChanged: Qt.callLater(sendHandoffs)
    function sendHandoffs() {
        // (which mods are on decides what is sent: wait for the list)
        if (!modsDoc) return
        var h = handoffs, top = 0
        for (var i = 0; i < h.length; i++) {
            if (h[i].seq <= sentUpTo) continue
            top = Math.max(top, h[i].seq)
            var mod = String(h[i].action).split(".")[0]
            // (another mod's action only while that mod is on: never an intent that does nothing)
            if (mod === "settings" || modOn(mod)) Store.act(h[i].action, h[i].args || {})
            // (its mod is off: the daemon says so, and brings the step back for an entry it was opening)
            else {
                var u = { seq: h[i].seq, action: h[i].action }
                if (h[i].key) u.key = h[i].key
                if (h[i].args && h[i].args.output) u.output = h[i].args.output
                Store.act("sessions.undelivered", u)
            }
        }
        if (top > 0) { sentUpTo = top; Store.act("sessions.handed", { seq: top }) }
    }
    readonly property var collect: firstHere ? (d.collect || null) : null
    readonly property bool collecting: collect !== null
    onCollectChanged: Qt.callLater(sendExtras)
    function sendExtras() {
        if (!collect) return
        var args = { project: collect.project, terminal: [] }
        var t = Store.docs["mod.terminal"]
        if (t && t.tabs) for (var i = 0; i < t.tabs.length; i++) {
            var dir = t.tabs[i].cwd || t.tabs[i].dir
            if (dir) args.terminal.push(String(dir))
        }
        var w = Store.docs["mod.webdock"]
        if (w && w.shown) args.webdock = String(w.shown)
        Store.act("sessions.desk.extras", args)
    }

    // ---- the step's rows: the targets, then the ticks ----
    readonly property bool shared: asking && c.state === "attached"
    readonly property var targets: {
        var t = d.targets || [], out = []
        for (var i = 0; i < t.length; i++) {
            var x = t[i], r = { kind: "target", id: x.id, label: I18n.tr(x.label), enabled: !x.reason, sub: "" }
            if (x.id === "kurashi") {
                r.icon = "terminal"
                r.enabled = modOn("terminal")
                r.sub = r.enabled ? I18n.tr("sessions.target.kurashi.sub") : I18n.tr("sessions.target.kurashi.off")
            } else if (x.id === "window") {
                r.icon = "open_in_new"
                r.sub = x.reason ? I18n.tr(x.reason) : I18n.tr("sessions.target.window.sub").replace("{program}", x.program || "")
            } else {
                r.icon = "desktop_windows"
                r.sub = I18n.tr("sessions.target.other.sub").replace("{program}", x.id)
            }
            out.push(r)
        }
        return out
    }
    property bool remember: false
    property bool restoreDesk: false
    readonly property var rows: {
        var r = targets.slice()
        r.push({ kind: "check", id: "remember", label: I18n.tr("sessions.step.remember"), enabled: true })
        if (asking && c.desk === true) r.push({ kind: "check", id: "desk", label: I18n.tr("sessions.step.desk"), enabled: true })
        return r
    }
    property int sel: 0
    function firstPick() {
        var want_ = (asking && c.project && d.settings) ? String(d.settings.open_in || "") : ""
        for (var i = 0; i < rows.length; i++) if (rows[i].kind === "target" && rows[i].enabled && rows[i].id === want_) return i
        for (var j = 0; j < rows.length; j++) if (rows[j].enabled) return j
        return 0
    }
    onWantChanged: if (want) {
        remember = false
        restoreDesk = c.restore === true
        sel = firstPick()
        keys.forceActiveFocus()
    }
    function move(by) {
        var j = sel
        for (var n = 0; n < rows.length; n++) {
            j = (j + by + rows.length) % rows.length
            if (rows[j].enabled) { sel = j; return }
        }
    }
    function pick(i) {
        var r = rows[i]
        if (!r || !r.enabled) return
        if (r.kind === "check") {
            if (r.id === "remember") remember = !remember
            else restoreDesk = !restoreDesk
            return
        }
        var args = { via: r.id, remember: remember }
        if (c.desk === true) args.desk = restoreDesk
        Store.act("sessions.choose", args)
    }
    function cancel() { Store.act("sessions.cancel") }

    // ---- the window: a card apart, centred, its shadow inside ----
    readonly property int shade: 24
    readonly property int cardW: 460
    screen: ch.screen
    visible: want || fade.running
    implicitWidth: cardW + 2 * shade
    implicitHeight: Math.max(1, body.implicitHeight + 2 * Theme.pad + 2 * shade)
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "kurashi-sessions-chooser"
    WlrLayershell.keyboardFocus: want ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Item {
        id: sheet
        x: ch.shade
        y: ch.shade
        width: ch.cardW
        height: ch.implicitHeight - 2 * ch.shade
        opacity: ch.want ? 1 : 0
        scale: ch.want || !Theme.springOn ? 1 : 0.96
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.springOn ? Theme.stdMs : 0; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.springOn ? Theme.stdMs : 0; easing.type: Easing.OutCubic } }

        MenuCard { anchors.fill: parent }
        MenuStyle { id: ms }

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onUpPressed: ch.move(-1)
            Keys.onDownPressed: ch.move(1)
            Keys.onTabPressed: ch.move(1)
            Keys.onBacktabPressed: ch.move(-1)
            Keys.onReturnPressed: ch.pick(ch.sel)
            Keys.onEnterPressed: ch.pick(ch.sel)
            Keys.onSpacePressed: { var r = ch.rows[ch.sel]; if (r && r.kind === "check") ch.pick(ch.sel) }
            Keys.onEscapePressed: ch.cancel()
            Keys.onPressed: function (e) {
                var n = e.key - Qt.Key_1
                if (n >= 0 && n < 9 && n < ch.targets.length) { e.accepted = true; ch.sel = n; ch.pick(n) }
            }

            Column {
                id: body
                x: Theme.pad
                y: Theme.pad
                width: parent.width - 2 * Theme.pad
                spacing: Theme.xs

                // The title: the session and its folder.
                Item {
                    width: parent.width
                    height: head.implicitHeight + Theme.gap
                    Column {
                        id: head
                        x: Theme.xs
                        width: parent.width - 2 * Theme.xs
                        spacing: 2
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: ch.asking ? I18n.tr("sessions.step.title").replace("{name}", "<b>" + String(ch.c.name).replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>") : ""
                            color: Theme.fg
                            font.pixelSize: Theme.fsTitle
                            font.family: Theme.tok("font.family", "sans-serif")
                            Accessible.role: Accessible.Heading
                            Accessible.name: ch.asking ? I18n.tr("sessions.step.title").replace("{name}", ch.c.name) : ""
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            elide: Text.ElideMiddle
                            text: ch.asking && ch.c.dir ? String(ch.c.dir) : ""
                            color: Theme.dim
                            font.pixelSize: Theme.fsLabel
                            font.family: Theme.tok("font.family_mono", "monospace")
                        }
                        Text {
                            width: parent.width
                            visible: ch.shared
                            wrapMode: Text.WordWrap
                            text: I18n.tr("sessions.step.shared")
                            color: Theme.dim
                            font.pixelSize: Theme.fsLabel
                        }
                    }
                }

                Repeater {
                    model: ch.rows
                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === ch.sel
                        readonly property bool check: modelData.kind === "check"
                        readonly property bool on: check && (modelData.id === "remember" ? ch.remember : ch.restoreDesk)
                        width: body.width
                        height: check ? 34 : 48
                        opacity: modelData.enabled ? 1 : 0.5
                        Accessible.role: check ? Accessible.CheckBox : Accessible.Button
                        Accessible.name: check ? modelData.label : I18n.tr("sessions.target.a11y").replace("{target}", modelData.label)
                        Accessible.description: modelData.sub || ""
                        Accessible.checkable: check
                        Accessible.checked: on
                        Accessible.focusable: true
                        Accessible.focused: selected

                        // The launcher's selection: its tonal block where the look leaves it, else the look's row face.
                        Block {
                            visible: row.selected && !ms.has && ms.highlight === "capsule"
                            anchors.fill: parent
                            anchors.bottomMargin: 2
                            radius: ms.radius(Theme.rLg)
                            ringScale: 0
                            softScale: 0
                            fill: Theme.selected
                            penSeed: 0x5E55
                        }
                        MenuRowFace {
                            id: face
                            anchors.fill: parent
                            anchors.bottomMargin: 2
                            highlighted: row.selected
                            enabled: row.modelData.enabled
                            checked: row.on
                        }
                        Rectangle {
                            // (a hairline above the ticks: they are not places to open)
                            visible: row.check && row.index > 0 && ch.rows[row.index - 1].kind === "target"
                            width: parent.width - 2 * Theme.gap
                            x: Theme.gap
                            height: 1
                            y: -Theme.xs / 2
                            color: Qt.alpha(Theme.fg, 0.12)
                        }
                        Icon {
                            id: ico
                            x: 10 + ms.lead
                            anchors.verticalCenter: parent.verticalCenter
                            name: row.check ? (row.on ? "check_box" : "check_box_outline_blank") : row.modelData.icon
                            filled: row.on
                            color: face.ink(row.selected ? Theme.fgOnSelected : (row.check ? Theme.dim : Theme.fg))
                        }
                        Column {
                            x: ico.x + 34
                            width: parent.width - x - 40
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.modelData.label
                                color: face.ink(row.selected ? Theme.fgOnSelected : Theme.fg)
                                font.pixelSize: Theme.fs
                                font.family: Theme.tok("font.family", "sans-serif")
                            }
                            Text {
                                width: parent.width
                                visible: !row.check && text !== ""
                                elide: Text.ElideRight
                                text: row.modelData.sub || ""
                                color: face.ink(Theme.dim)
                                font.pixelSize: Theme.fsCaption
                            }
                        }
                        // The number key that opens it.
                        Text {
                            visible: !row.check && row.index < 9
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.pad
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(row.index + 1)
                            color: face.ink(Theme.dim)
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.tok("font.family_mono", "monospace")
                        }
                        FocusRing { anchors.fill: parent; shown: row.selected && keys.activeFocus && ms.has; corner: Theme.rSm }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: row.modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onEntered: if (row.modelData.enabled) ch.sel = row.index
                            onClicked: ch.pick(row.index)
                        }
                    }
                }

                // The keys, and a cancel for the pointer.
                Item {
                    width: parent.width
                    height: 28
                    Text {
                        x: Theme.xs
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - cancelB.width - Theme.gap
                        elide: Text.ElideRight
                        text: I18n.tr("sessions.step.keys")
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                    }
                    IconButton {
                        id: cancelB
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "close"
                        a11y: I18n.tr("sessions.step.cancel")
                        onClicked: ch.cancel()
                    }
                }
            }
        }
    }
}
