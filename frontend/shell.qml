import QtQuick
import Quickshell
import "core"
import "core/mods.js" as Mods
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
    // The quick card is wanted too (B14): a change of `want` re-picks the output, so the card opens on the focused one.
    readonly property bool want: !!ui && (ui.panel === undefined ? ui.popup === true
        : ui.panel === "island" || ui.panel === "session" || ui.panel === "tray" || ui.panel === "quick")
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
    // The mods' own surfaces (K38, row 88): every enabled mod's `surface:<name>`, once per output, with that output as its
    // `screen` (a required property at creation, so ModLoader, which hands in only the core singletons, does not fit).
    // They live as long as their mod: the list changes only when its content does (a Repeater would rebuild them all).
    Watch { doc: "mods" }
    readonly property var modsDoc: Store.docs["mods"]
    property var surfaceList: []
    function refreshSurfaces() {
        var s = Mods.surfaces(modsDoc)
        if (JSON.stringify(s) !== JSON.stringify(surfaceList)) surfaceList = s
    }
    onModsDocChanged: refreshSurfaces()
    Component.onCompleted: refreshSurfaces()
    Variants {
        model: Quickshell.screens
        // An Item holds the Repeater (a Repeater under a non-visual parent makes no delegates).
        delegate: Item {
            id: perScreen
            required property var modelData
            Repeater {
                model: root.surfaceList
                delegate: Loader {
                    required property var modelData
                    Component.onCompleted: setSource(modelData.url, { screen: perScreen.modelData })
                    onStatusChanged: if (status === Loader.Error) console.warn("shell: cannot load " + modelData.url)
                }
            }
        }
    }
    // Desktop widgets (K43): one per output, on the bottom layer; no surface while desktop.enabled is off.
    Variants {
        model: Quickshell.screens
        delegate: Desktop {}
    }
    // The app dock (K51): per output, only while dock.enabled is on there (no surface otherwise).
    Variants {
        model: Quickshell.screens
        delegate: Dock {}
    }
    // Rounded screen corners (K47 (6)): per output, only while theme.shape.screen_corners > 0.
    Variants {
        model: Quickshell.screens
        delegate: ScreenCorners {}
    }
    // The edge sidebars (W29, docs/ux/sidebar.md): a window only while runtime.ui.sidebar names its side, on that output.
    Sidebar { side: "right"; focusedScreen: root.focusedScreen() }
    Sidebar { side: "left"; focusedScreen: root.focusedScreen() }
    Lock {}
    // One Stage for the whole shell, retargeted to the focused output (K16). Destroying and
    // re-creating it per open leaked ~5 MiB of heap per cycle (measured), a persistent unmapped
    // one costs less than that and keeps first-open latency low.
    Toasts { screen: root.focusedScreen() }
    Launcher {}
    // The polkit agent (K47 (5)): its dialog exists only while a request is up.
    PolkitDialog {}
    Stage {
        screen: root.stageScreen
        want: root.stageOpen
    }
}
