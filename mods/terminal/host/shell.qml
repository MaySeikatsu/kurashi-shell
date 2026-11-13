// The terminal's host (W83; docs/ux/terminal.md; MODS.md "Host processes"): a Quickshell config with QMLTermWidget,
// which the daemon starts while a session exists or a place is open, and stops when neither holds — never on an idle
// clock, which would end the user's programs. It connects with the scope the daemon handed it, watches `mod.terminal`,
// `theme` and `i18n`, owns one pty per tab, and draws the text in one layer window over the well of the place that shows
// the terminal (`shown_in`, at `rests[shown_in]`); the shell draws the place itself, its material shows through. While
// that place moves or nothing shows the terminal the window is unmapped (0 frames); the sessions keep running.
//   qs-terminal -p mods/terminal/host/shell.qml
import QtQuick
import Quickshell
import Quickshell.Io
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

    // The stills of an earlier host (its tabs are gone; a new tab may take an old id): cleared as this one starts.
    Process {
        running: true
        command: ["sh", "-c", "rm -f \"${XDG_RUNTIME_DIR:-/tmp}\"/kurashi-terminal-*.png"]
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
        // The last place the well rested: kept while unmapped, so the terminal keeps its rows and columns (a window shrunk
        // to nothing would resize every shell to one column, and the screen would come back empty).
        property var last: ({ output: "", x: 0, y: 0, width: 800, height: 400 })
        Connections {
            target: root
            function onRestChanged() { if (root.rest) place.last = root.rest }
        }
        Component.onCompleted: if (root.rest) last = root.rest
        screen: screenFor(last.output)
        readonly property bool mapped: root.rest !== null && root.active !== "" && Store.connected
        // Shown: follows `mapped`, but an unmap waits for the last still (one frame), so the place can draw the text as it
        // leaves. The text arrives with the place at rest: a cut over the still the place drew while it moved (the same
        // pixels), else (no still of that size yet: the first show) a short fade; a cut under reduced motion.
        property bool shown: false
        onMappedChanged: {
            if (mapped) {
                var v = viewOf(root.active)
                var still = v && v.hasStill(last.width, last.height)
                content.opacity = 1
                if (!still && Theme.motionKind !== "none") fadeIn.restart()
                shown = true
                return
            }
            // (a frame after the place drew its still: the same pixels go from over it, never a frame with neither)
            var cur = viewOf(root.active)
            if (cur && shown) cur.flush(function () { unmapLater.restart() })
            else shown = false
        }
        visible: shown
        Timer {
            id: unmapLater
            interval: 17
            onTriggered: if (!place.mapped) place.shown = false
        }
        // Where the text is now, for the places (they put their still away once it is here): reported after the first
        // frame of a map, and on the unmap.
        property string reportedAt: ""
        // The stills written (newest first; the places draw only these), sent with the next report.
        property var stillKeys: []
        property bool stillsNew: false
        property int stillGen: 0
        // (said at once while the text shows: the place keeps the newest still loaded, to draw it the moment it leaves)
        function wroteStill(k) {
            stillKeys = [k].concat(stillKeys.filter(function (x) { return x !== k })).slice(0, 16)
            stillGen++
            stillsNew = true
            if (shown && visible) reportShown()
        }
        function reportShown() {
            var at = shown && visible ? root.shownIn : ""
            if (at === reportedAt && !stillsNew) return
            reportedAt = at
            var args = at !== "" ? { where: at } : {}
            if (stillsNew) { args.stills = stillKeys; args.gen = stillGen; stillsNew = false }
            root.report("terminal.host.shown", args)
        }
        onShownChanged: if (!shown) reportShown()
        Connections {
            target: root
            function onShownInChanged() { if (place.visible) shownLater.restart() }
        }
        Timer {
            id: shownLater
            interval: 32
            onTriggered: place.reportShown()
        }
        onVisibleChanged: if (visible) shownLater.restart()
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "kurashi-terminal"
        anchors.top: true
        anchors.left: true
        margins.top: last.y
        margins.left: last.x
        implicitWidth: Math.max(1, last.width)
        implicitHeight: Math.max(1, last.height)

        // The keyboard. Out as the drop-down it is the terminal's while it shows (Yakuake): exclusive, so no click on a
        // window steals the shell's keys (`keys`), until a click elsewhere (the sheet's click-away) hides it (`hide_on_blur`)
        // or gives the keyboard back (kept open): then on demand, a click in the terminal takes it again. In the card and the
        // sidebar it is on demand. (niri drops a layer's keyboard when it turns from exclusive to on demand: no pulse.)
        readonly property bool dropdown: root.shownIn === "dropdown"
        property bool winActive: false
        // (the shell's chrome holds it now — a menu out of the tab row, a tab's name edited: `held`)
        WlrLayershell.keyboardFocus: root.doc.held === true ? WlrKeyboardFocus.None
            : visible && dropdown && root.doc.keys === true ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

        function viewOf(id) {
            for (var i = 0; i < views.count; i++) {
                var v = views.itemAt(i)
                if (v && v.tabId === id) return v
            }
            return null
        }

        Item {
            id: content
            // (sized from the last rest, not the window: an unmapped window's content shrinks to nothing, and the shells
            // with it)
            width: Math.max(1, place.last.width)
            height: Math.max(1, place.last.height)
            // (the fade: started on the map, not bound to it: an animation in an unmapped window does not run, and a bound fade
            // to 0 on the unmap was left there)
            NumberAnimation {
                id: fadeIn
                target: content
                property: "opacity"
                from: 0
                to: 1
                duration: 90
                easing.type: Easing.OutCubic
            }
            Repeater {
                id: views
                model: tabModel
                // (TermView's required `tabId` is the model's role)
                delegate: TermView {
                    anchors.fill: parent
                    tab: root.tabOf(tabId) || ({ id: tabId })
                    active: tabId === root.active
                    shownNow: place.visible
                    wrote: place.wroteStill
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
