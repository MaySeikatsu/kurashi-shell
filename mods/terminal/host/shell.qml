// The terminal's host (W83; docs/ux/terminal.md; MODS.md "Host processes"): a Quickshell config with QMLTermWidget,
// which the daemon starts while a session exists or a place is open, and stops when neither holds — never on an idle
// clock, which would end the user's programs. It connects with the scope the daemon handed it, watches `mod.terminal`,
// `theme` and `i18n`, owns one pty per tab, and draws the text in one layer window over the well of the place that shows
// the terminal (`shown_in`, at `rests[shown_in]`); the shell draws the place itself, its material shows through. While
// that place moves or nothing shows the terminal the window is unmapped (0 frames); the sessions keep running.
//   qs-terminal -p mods/terminal/host/shell.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import "core"

ShellRoot {
    id: root

    Watch { doc: "mod.terminal" }
    Watch { doc: "theme" }
    Watch { doc: "i18n" }

    readonly property var doc: Store.docs["mod.terminal"] || ({})
    readonly property var tabs: doc.tabs || []
    readonly property var settings: doc.settings || ({})
    readonly property string active: doc.active || ""
    readonly property string shownIn: doc.shown_in || ""
    readonly property var rest: shownIn !== "" && doc.rests ? (doc.rests[shownIn] || null) : null
    readonly property bool debugLog: Quickshell.env("KURASHI_TERMINAL_DEBUG") === "1"

    function report(action, args) {
        if (debugLog) console.log("terminal-debug sent " + action + " " + JSON.stringify(args))
        Store.act(action, args, function (done, err) {
            if (err) console.warn("terminal: " + action + " refused: " + err.kind + " " + err.msg)
        })
    }
    function tabOf(id) {
        for (var i = 0; i < tabs.length; i++) if (tabs[i].id === id) return tabs[i]
        return null
    }
    function runsOf(id) {
        var r = doc.runs || []
        return r.filter(function (x) { return x.tab === id })
    }

    // The daemon did not issue this scope: a host it does not know must not linger with the user's shells.
    Connections {
        target: Store
        function onRefusedChanged() {
            if (Store.refused !== "") {
                console.warn("terminal: the daemon refused this host's scope; exiting")
                Qt.quit()
            }
        }
    }

    // The sessions, keyed by tab id: a delegate is made when its tab appears and destroyed (its shell hung up) when the
    // tab leaves the document — never remade because another field of the document changed.
    ListModel { id: tabModel }
    onTabsChanged: syncTabs()
    function syncTabs() {
        var want = {}
        for (var i = 0; i < tabs.length; i++) want[tabs[i].id] = true
        for (var j = tabModel.count - 1; j >= 0; j--)
            if (!want[tabModel.get(j).tabId]) tabModel.remove(j)
        var have = {}
        for (var k = 0; k < tabModel.count; k++) have[tabModel.get(k).tabId] = true
        for (var m = 0; m < tabs.length; m++)
            if (!have[tabs[m].id]) tabModel.append({ tabId: tabs[m].id })
    }

    // Status for the bar (`bar_mode = status`): the active tab's foreground program and directory, once a second while
    // the bar shows them and a tab exists. Nothing polls in the other modes (Ma).
    readonly property bool watchStatus: settings.bar_mode === "status" && active !== ""
    property var lastStatus: ({})
    Timer {
        interval: 1000
        repeat: true
        running: root.watchStatus
        triggeredOnStart: true
        onTriggered: {
            var v = place.viewOf(root.active)
            if (!v || !v.started) return
            var prog = v.session.hasActiveProcess ? String(v.session.foregroundProcessName || "") : ""
            var cwd = String(v.session.currentDir || "")
            var last = root.lastStatus[root.active] || {}
            if (last.prog === prog && last.cwd === cwd) return
            root.lastStatus[root.active] = { prog: prog, cwd: cwd }
            root.report("terminal.host.title", { tab: root.active, program: prog, cwd: cwd })
        }
    }

    PanelWindow {
        id: place
        function screenFor(name) {
            var all = Quickshell.screens
            for (var i = 0; i < all.length; i++) if (all[i].name === name) return all[i]
            return all.length > 0 ? all[0] : null
        }
        screen: screenFor(root.rest ? root.rest.output : "")
        readonly property bool mapped: root.rest !== null && root.active !== "" && Store.connected
        visible: mapped
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "kurashi-terminal"
        anchors.top: true
        anchors.left: true
        margins.top: root.rest ? root.rest.y : 0
        margins.left: root.rest ? root.rest.x : 0
        implicitWidth: root.rest ? Math.max(1, root.rest.width) : 1
        implicitHeight: root.rest ? Math.max(1, root.rest.height) : 1

        // The keyboard. Out as the drop-down it is the terminal's while it shows (Yakuake): exclusive, so no click on a
        // window steals the shell's keys; the toggle takes it back (and `hide_on_blur` hides it on a click elsewhere, through
        // the sheet's click-away). In the card and the sidebar it is on demand: a click in the terminal takes it. niri drops
        // a layer's keyboard when it turns from exclusive to on demand, so the drop-down does not pulse.
        readonly property bool dropdown: root.shownIn === "dropdown"
        property bool winActive: false
        WlrLayershell.keyboardFocus: visible && dropdown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        function viewOf(id) {
            for (var i = 0; i < views.count; i++) {
                var v = views.itemAt(i)
                if (v && v.tabId === id) return v
            }
            return null
        }

        Item {
            id: content
            anchors.fill: parent
            // The text arrives with the place at rest: a short fade, a cut under reduced motion.
            opacity: place.visible ? 1 : 0
            Behavior on opacity {
                enabled: Theme.motionKind !== "none"
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
            Repeater {
                id: views
                model: tabModel
                // (TermView's required `tabId` is the model's role)
                delegate: TermView {
                    anchors.fill: parent
                    tab: root.tabOf(tabId) || ({ id: tabId })
                    active: tabId === root.active
                    settings: root.settings
                    runs: root.runsOf(tabId)
                    report: root.report
                    onActiveChanged: if (active && place.winActive) term.forceActiveFocus()
                }
            }
            HoverHandler {
                onHoveredChanged: root.report("terminal.host.hover", { on: hovered })
            }
            Window.onActiveChanged: {
                place.winActive = Window.active
                if (Window.active) {
                    var v = place.viewOf(root.active)
                    if (v) v.term.forceActiveFocus()
                }
            }
        }

        // Yakuake's and Konsole's tab keys (docs/ux/terminal.md "Keyboard"); every other key, Esc included, is the shell's.
        Shortcut { sequence: "Ctrl+Shift+T"; onActivated: root.report("terminal.new_tab", {}) }
        Shortcut { sequence: "Ctrl+Shift+W"; onActivated: if (root.active !== "") root.report("terminal.close_tab", { tab: root.active }) }
        Shortcut { sequence: "Ctrl+PgDown"; onActivated: root.report("terminal.select", { step: 1 }) }
        Shortcut { sequence: "Ctrl+PgUp"; onActivated: root.report("terminal.select", { step: -1 }) }
        Shortcut {
            sequence: "Ctrl+Shift+PgDown"
            onActivated: root.moveActive(1)
        }
        Shortcut {
            sequence: "Ctrl+Shift+PgUp"
            onActivated: root.moveActive(-1)
        }
        Shortcut {
            sequence: "Ctrl+Shift+C"
            onActivated: { var v = place.viewOf(root.active); if (v) v.term.copyClipboard() }
        }
        Shortcut {
            sequences: ["Ctrl+Shift+V", "Shift+Insert"]
            onActivated: { var v = place.viewOf(root.active); if (v) v.term.pasteClipboard() }
        }
    }
    function moveActive(by) {
        for (var i = 0; i < tabs.length; i++)
            if (tabs[i].id === active) { report("terminal.move_tab", { tab: active, to: i + by }); return }
    }
}
