import QtQuick
import Quickshell
import "core"
import "core/mods.js" as Mods
import "surfaces"
import "components/island"
import "components/menus"

// Thin view (CLAUDE.md rule 1): the bars of each output; Quickshell.screens follows hotplug.
// A single content-sized Stage serves the focused output only (K16).
ShellRoot {
    id: root
    ColorBlend {}

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
    // (B126, session 30: a mod's card — `mod:<id>:<panel>`, the web dock's, the weather's — is wanted too; it was not, so
    // its screen was never picked again and it opened where the last card had been)
    readonly property bool want: !!ui && (ui.panel === undefined ? ui.popup === true
        : ui.panel === "island" || ui.panel === "session" || ui.panel === "tray" || ui.panel === "quick"
            || String(ui.panel || "").indexOf("mod:") === 0)
    // B126: where a card opens — the screen whose bar module was pressed just now (a press on a bar does not move the
    // compositor's focus to that screen), else the focused one (a key, the command line).
    function openScreen() {
        var lp = IslandGeom.lastPress
        if (lp && lp.output && Date.now() - lp.t < 1500) {
            var s = Quickshell.screens
            for (var i = 0; i < s.length; i++) if (s[i].name === lp.output) return s[i]
        }
        return focusedScreen()
    }
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
        if (want) stageScreen = (ui && ui.panel === "tray" && trayOrigin) ? trayOrigin : openScreen()
        else trayOrigin = null
        hopping = false
        stageOpen = want
    }
    // Session 28 (`bar.popups_follow`, on by default): a card that was opened on purpose — a click, a key, the command
    // line — follows the pointer to another screen: the compositor's focused output changes (the daemon's
    // `svc.workspaces`), the card folds where it is and opens on that screen, under the same module where its bar has
    // it. Not what a hover opened (it closes as the pointer leaves it), not a tray item's menu (it belongs to its icon),
    // and never a sidebar (a surface of its own, on its own screen), nor a kept card (B128).
    readonly property bool follows: {
        var c = Store.docs["config"], p = c && c.values ? c.values["bar.popups_follow"] : undefined
        return p === undefined || p.value !== false
    }
    property bool hopping: false
    readonly property var nowFocused: { var d = Store.docs["svc.workspaces"]; return focusedScreen() }
    onNowFocusedChanged: {
        if (!stageOpen || hopping || !follows || !nowFocused || nowFocused === stageScreen) return
        if (Peeks.hoverOwner !== "" || (ui && ui.panel === "tray")) return
        // B128 (session 32, the user): a kept card (`ui.keep`, K147 — the web dock's bar card pinned) stays on the screen
        // where it was kept; only a card that is not kept follows the focus.
        if (ui && ui.kept !== undefined && ui.kept === ui.panel) return
        hopping = true
        hopLimit.restart()
    }
    function hopLand() {
        if (!hopping) return
        hopLimit.stop()
        if (want) stageScreen = hopTarget !== null ? hopTarget : focusedScreen()
        hopTarget = null
        hopping = false
    }
    // B126: another card asked for while one is open (`want` stays true) by a press on another screen's bar — the card
    // folds here and opens there, as a card that follows the pointer does.
    property var hopTarget: null
    readonly property string panelNow: ui ? String(ui.panel || "") : ""
    onPanelNowChanged: {
        if (!stageOpen || hopping || !want || (ui && ui.panel === "tray")) return
        var lp = IslandGeom.lastPress
        if (!lp || !lp.output || Date.now() - lp.t >= 1500) return
        var s = openScreen()
        if (!s || s === stageScreen) return
        hopTarget = s
        hopping = true
        hopLimit.restart()
    }
    // (a card that does not report it is gone must not stay held)
    Timer { id: hopLimit; interval: 900; onTriggered: root.hopLand() }

    Watch { doc: "theme" }
    Watch { doc: "i18n" }
    Watch { doc: "svc.workspaces" }
    Watch { doc: "runtime.ui" }
    // Colour flow that runs while music plays reads the player's state (core/ColorFlow.qml); only then (rule 5).
    Watch { doc: "svc.media"; active: ColorFlow.wantsMedia }

    // The bars and the screen frame of each output (K71, docs/ux/layout.md, docs/ux/frame.md): a bar on every edge whose
    // `runtime.layout` entry has one, and the frame's strips while the frame is on. Mapping order matters (a zone holder is
    // placed inside the zones of the holders mapped before it): the top and bottom bars first, the frame's top and bottom
    // strips, then the side bars — which run between the horizontal bars — once those are on screen.
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: edges
            required property var modelData
            Bar { id: topBar; modelData: edges.modelData; edge: "top"; onTrayMenuRequested: id => root.openTray(id, edges.modelData) }
            Bar { id: bottomBar; modelData: edges.modelData; edge: "bottom"; onTrayMenuRequested: id => root.openTray(id, edges.modelData) }
            Frame { id: frame; modelData: edges.modelData }
            Bar {
                modelData: edges.modelData
                edge: "left"
                after: topBar.settled && bottomBar.settled && frame.acrossSettled
                onTrayMenuRequested: id => root.openTray(id, edges.modelData)
            }
            Bar {
                modelData: edges.modelData
                edge: "right"
                after: topBar.settled && bottomBar.settled && frame.acrossSettled
                onTrayMenuRequested: id => root.openTray(id, edges.modelData)
            }
        }
    }
    // Session 28 (I472/I478): a bar that changes its edge travels there (core/Travel.qml); made only for a move.
    Variants {
        model: Quickshell.screens
        delegate: Traveller {}
    }
    // The edge modules of each output (K71, K72, docs/ux/edge-modules.md): every non-empty zone of an edge without a bar is
    // a group pinned to that edge, mapped after the bars and the frame (a zone-holding group is placed inside their zones).
    Variants {
        model: Quickshell.screens
        delegate: EdgeModules { id: edgeMods; onTrayMenuRequested: id => root.openTray(id, edgeMods.modelData) }
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
    // Desktop widgets (K43): one per output, on the bottom layer; no window at all while desktop.enabled is off there (B35:
    // a hidden window still made its whole tree of cards — with the overlay below, ~16 MiB at one output and ~10.6 MiB per
    // extra output, W35 bench).
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: deskScope
            required property var modelData
            BarConfig { id: deskCfg; screen: deskScope.modelData }
            LazyLoader {
                active: deskCfg.valueOf("desktop.enabled", false) === true
                Desktop { modelData: deskScope.modelData }
            }
        }
    }
    // The app dock (K51): per output, only while dock.enabled is on there (no surface otherwise).
    Variants {
        model: Quickshell.screens
        delegate: Dock {}
    }
    // The shared hover strips at the edges (K71, EdgeStrips): per output, a strip only while something there reveals on hover.
    Variants {
        model: Quickshell.screens
        delegate: EdgeStripHost {}
    }
    // The desktop's right click (W82, docs/ux/context-menus.md): one empty window per output over the wallpaper.
    DeskCatches {}
    // A click elsewhere closes an open card, the launcher or the notification centre (I279): per output, only while one is open.
    Variants {
        model: Quickshell.screens
        delegate: ClickAway {}
    }
    // Rounded screen corners (K47 (6)): per output, only while runtime.layout's screen_radius > 0 (K74).
    Variants {
        model: Quickshell.screens
        delegate: ScreenCorners {}
    }
    // The edge sidebars (W29, docs/ux/sidebar.md): a window only while runtime.ui.sidebar names its side, on that output.
    Sidebar { side: "right"; focusedScreen: root.focusedScreen() }
    Sidebar { side: "left"; focusedScreen: root.focusedScreen() }
    Lock {}
    // The material's relief over every output, apps included (K59, scope everything): a window only while that scope is on
    // (made then, not kept hidden: B35).
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: overlayScope
            required property var modelData
            LazyLoader {
                active: Theme.texOverlay
                TextureOverlay { modelData: overlayScope.modelData }
            }
        }
    }
    // One Stage for the whole shell, retargeted to the focused output (K16). Destroying and
    // re-creating it per open leaked ~5 MiB of heap per cycle (measured), a persistent unmapped
    // one costs less than that and keeps first-open latency low.
    Toasts { screen: root.focusedScreen() }
    // I527 (session 33): the OSD, on the focused output (docs/ux/osd.md).
    Osd { screen: root.focusedScreen() }
    Launcher {}
    // The polkit agent (K47 (5)): its dialog exists only while a request is up.
    PolkitDialog {}
    // The pointer decoration (W53.0b, I317): a sheet only while the pointer moves with a decoration on.
    Effects {}
    Stage {
        screen: root.stageScreen
        want: root.stageOpen
        hold: root.hopping
        onShownChanged: if (!shown) root.hopLand()
    }
}
