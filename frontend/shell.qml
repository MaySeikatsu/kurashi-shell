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
    readonly property bool want: (Store.docs["runtime.ui"] && Store.docs["runtime.ui"].popup) === true
    property bool stageOpen: false      // follows want, but only after the screen is re-picked
    onWantChanged: { if (want) stageScreen = focusedScreen(); stageOpen = want }

    Watch { doc: "theme" }
    Watch { doc: "i18n" }
    Watch { doc: "svc.workspaces" }
    Watch { doc: "runtime.ui" }

    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }
    // One Stage for the whole shell, retargeted to the focused output (K16). Destroying and
    // re-creating it per open leaked ~5 MiB of heap per cycle (measured), a persistent unmapped
    // one costs less than that and keeps first-open latency low.
    Launcher {}
    Stage {
        screen: root.stageScreen
        want: root.stageOpen
    }
}
