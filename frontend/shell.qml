import QtQuick
import Quickshell
import "core"
import "surfaces"

// Thin view (CLAUDE.md rule 1): one Bar per output; Quickshell.screens follows hotplug.
// A single content-sized Stage serves the focused output only (K16).
ShellRoot {
    id: root

    // Output whose workspace list holds the focused workspace; first screen as fallback.
    function focusedScreen() {
        var o = (Store.docs["svc.workspaces"] && Store.docs["svc.workspaces"].outputs) || {}
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) {
            var l = o[s[i].name] || []
            for (var j = 0; j < l.length; j++)
                if (l[j].focused) return s[i]
        }
        return s.length > 0 ? s[0] : null
    }

    // Latched while the popup is open so it never jumps outputs; re-picked on each open.
    property var stageScreen: focusedScreen()
    // The Stage shows the island panel and the session menu; notifications have their own surface.
    // (The probe-era mock has no `panel`, only `popup`.)
    readonly property var ui: Store.docs["runtime.ui"]
    readonly property bool want: !!ui && (ui.panel === undefined ? ui.popup === true
        : ui.panel === "island" || ui.panel === "session" || ui.panel === "tray")
    property bool stageOpen: false      // follows want, but only after the screen is re-picked

    // The output whose tray item was clicked: its menu opens there, not on the focused output. Set
    // before the daemon is asked, so the Stage has its screen when the panel comes up.
    property var trayOrigin: null
    function openTray(id, origin) {
        trayOrigin = origin
        stageScreen = origin
        Store.act("tray.menu.open", {id: id})
    }
    onWantChanged: {
        if (want) stageScreen = (ui && ui.panel === "tray" && trayOrigin) ? trayOrigin : focusedScreen()
        else trayOrigin = null
        stageOpen = want
    }

    Watch { doc: "theme" }
    Watch { doc: "i18n" }
    Watch { doc: "svc.workspaces" }
    Watch { doc: "runtime.ui" }

    Variants {
        model: Quickshell.screens
        delegate: Bar {
            onTrayMenuRequested: id => root.openTray(id, screen)
        }
    }
    Lock {}
    // One Stage for the whole shell, retargeted to the focused output (K16). Destroying and
    // re-creating it per open leaked ~5 MiB of heap per cycle (measured), a persistent unmapped
    // one costs less than that and keeps first-open latency low.
    Toasts { screen: root.focusedScreen() }
    Launcher {}
    Stage {
        screen: root.stageScreen
        want: root.stageOpen
    }
}
