import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../core/mods.js" as Mods
import "../components"

// One bar per output, on the edge that output's config names (bar.edge). bar.enabled false: no
// surface, no exclusive zone and no subscriptions held for it (Ma). Everything shown comes from
// Store; every click becomes an act/intent.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    // This output's bar settings (config document, per-output entry wins).
    BarConfig { id: cfg; screen: bar.screen }
    readonly property bool vertical: cfg.vertical
    // The bar's edge, kept by Peeks for this output: the items' peeks ask for it, and a side bar's peek sits beside the bar (I67).
    readonly property string barEdge: cfg.edge
    onBarEdgeChanged: Peeks.setEdge(screen ? screen.name : "", barEdge)

    readonly property string origin: "qs:" + (screen ? screen.name : "?") + ":" + Math.floor(Math.random() * 1e6)
    // Veil: daemon away (or not yet current) -> keep last state, dim it, show the glyph.
    readonly property bool stale: !Store.live

    // What this bar renders; unwatched while the bar is hidden or gone so the daemon can stop
    // services nobody shows (Ma).
    Watch { doc: "svc.clock"; active: bar.visible }
    Watch { doc: "svc.workspaces"; active: bar.visible }
    Watch { doc: "runtime.island.main"; active: bar.visible }
    Watch { doc: "svc.audio"; active: bar.visible }
    Watch { doc: "mods"; active: bar.visible }
    Watch { doc: "svc.tray"; active: bar.visible }
    // Input bindings (ARCHITECTURE §6): what each island slot runs. Only while this bar is shown.
    Watch { doc: "bindings"; active: bar.visible }
    readonly property var clock: Store.docs["svc.clock"] || ({})
    readonly property var workspaces: Store.docs["svc.workspaces"] || ({})
    readonly property var island: Store.docs["runtime.island.main"] || ({})
    // Volume. The slider shows a level only for audio the daemon reports: no document yet, or
    // available === false (no audio server; its volume there is 0), is no level, not a guessed 0 %.
    // A muted sink keeps its level, drawn dim (Shōjiki, B2).
    readonly property var audioDoc: Store.docs["svc.audio"]
    readonly property var audio: audioDoc || ({})
    readonly property bool audioUsable: audioDoc !== undefined && audioDoc.available !== false
    readonly property bool audioMuted: audio.muted === true
    // Mod widgets (K26): every enabled mod's `widget:*` component, in mod order, placed at the end of the right row.
    // The list is rebuilt only when its content changes: a Repeater reset would reload every widget.
    readonly property var modsDoc: Store.docs["mods"]
    property var modWidgets: []
    function refreshWidgets() {
        var w = Mods.widgets(modsDoc)
        if (JSON.stringify(w) !== JSON.stringify(modWidgets)) modWidgets = w
    }
    onModsDocChanged: refreshWidgets()
    Component.onCompleted: { refreshWidgets(); Peeks.setEdge(screen ? screen.name : "", barEdge) }
    // A mod widget's peek (K35): its `peek:<name>` component, named after the widget's `widget:<name>`; "" when the mod has none.
    function modPeekOf(w) {
        var name = String(w.provide).substring("widget:".length)
        return Mods.qmlOf(modsDoc, "peek:" + name, w.mod) !== "" ? "mod:" + w.mod + ":" + name : ""
    }
    readonly property var trayDoc: Store.docs["svc.tray"] || ({})
    readonly property var bindings: Store.docs["bindings"] || ({})
    // Items to draw: none while the tray service is unavailable, and Passive items stay hidden
    // (status Passive says there is nothing to show). No delegates exist for the others.
    readonly property var trayItems: trayDoc.available === true
        ? (trayDoc.items || []).filter(function (it) { return it.status !== "Passive" }) : []
    // A tray menu is shown by the Stage on the output whose tray was clicked (shell.qml).
    signal trayMenuRequested(string id)
    readonly property real daemonVolume: audio.volume ?? 0
    readonly property string volumeA11y: !audioUsable ? I18n.tr("frontend.volume.unavailable")
        : (audioMuted ? I18n.tr("frontend.volume.muted")
            : I18n.tr("frontend.volume.level").replace("{pct}", Math.round(daemonVolume * 100)))
    // This output's workspace pills, or the "*" list when the daemon sends one for all outputs.
    readonly property var pills: {
        var o = workspaces.outputs || {}
        var n = screen ? screen.name : ""
        return o[n] || o["*"] || []
    }

    // Screen coordinates of a point in `item`: the SNI calls take them. The surface sits at the
    // output's top-left, or at its bottom or right edge for a bar on those sides.
    function screenPoint(item, x, y) {
        var p = item.mapToItem(null, x, y)
        var s = bar.screen
        var ox = s && cfg.edge === "right" ? s.width - bar.width : 0
        var oy = s && cfg.edge === "bottom" ? s.height - bar.height : 0
        return { x: Math.round((s ? s.x : 0) + ox + p.x), y: Math.round((s ? s.y : 0) + oy + p.y) }
    }
    // A tray click. A menu request goes to the shell, which knows the output the Stage shows it on;
    // the other buttons are sent here, as tray.activate or tray.secondary.
    function trayRequest(action, id, item, x, y) {
        if (action === "menu") { bar.trayMenuRequested(id); return }
        var p = screenPoint(item, x, y)
        Store.act(action === "secondary" ? "tray.secondary" : "tray.activate", {id: id, x: p.x, y: p.y})
    }

    // One tray item, the same in both layouts. The bar's full thickness is its pointer target.
    Component {
        id: trayIconDelegate
        TrayIcon {
            id: ticon
            required property var modelData
            title: modelData.title ?? ""
            iconName: modelData.icon_name ?? ""
            iconTheme: modelData.icon_theme_path ?? ""
            pixmap: (modelData.icon_pixmap && modelData.icon_pixmap.png_base64)
                ? "data:image/png;base64," + modelData.icon_pixmap.png_base64 : ""
            attention: modelData.status === "NeedsAttention"
            hasMenu: modelData.has_menu === true
            menuOnly: modelData.item_is_menu === true
            tip: modelData.tooltip ?? ""
            // The hover peek names the item's title and tooltip (K35, B9); an item with neither has nothing to show.
            peekSource: (modelData.title || modelData.tooltip) ? "tray:" + modelData.id : ""
            peekOutput: bar.screen ? bar.screen.name : ""
            onRequested: (action, x, y) => bar.trayRequest(action, modelData.id, ticon, x, y)
            onScrolled: (delta, orientation) =>
                Store.act("tray.scroll", {id: modelData.id, delta: delta, orientation: orientation})
        }
    }

    // Volume intents. A wheel notch is one 5 % step from the last value sent, so fast scrolling
    // does not lose steps while the daemon's echo is still on its way; the echo resets it.
    property real volumeTarget: -1
    onDaemonVolumeChanged: volumeTarget = -1
    function setVolume(v) {
        if (!audioUsable) return
        volumeTarget = -1
        Store.intent("audio.volume", v, origin)
    }
    function volumeStep(dy) {
        if (dy === 0 || !audioUsable) return
        var base = volumeTarget >= 0 ? volumeTarget : daemonVolume
        volumeTarget = Math.max(0, Math.min(1, base + (dy > 0 ? 0.05 : -0.05)))
        Store.intent("audio.volume", volumeTarget, origin)
    }

    // Anchored to its edge: a left or right bar spans the height, a top or bottom bar the width.
    anchors {
        top: cfg.edge === "top" || vertical
        bottom: cfg.edge === "bottom" || vertical
        left: cfg.edge === "left" || !vertical
        right: cfg.edge === "right" || !vertical
    }
    implicitHeight: vertical ? 0 : Theme.barH
    implicitWidth: vertical ? Theme.barH : 0
    visible: cfg.enabled
    color: "transparent"       // exclusionMode Auto -> exclusive zone = the bar's thickness

    // ext-background-effect-v1 blur (no-op where the compositor lacks the protocol)
    BackgroundEffect.blurRegion: Region { item: bg }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Theme.surfaceAlpha
    }

    // One layout is active at a time: a row on top and bottom bars, a column on left and right.
    // Nothing is instantiated while the bar is hidden, so its faces hold no subscriptions (Ma).
    Loader {
        anchors.fill: parent
        active: bar.visible && !bar.vertical
        sourceComponent: horizontalLayout
    }
    Loader {
        anchors.fill: parent
        active: bar.visible && bar.vertical
        sourceComponent: verticalLayout
    }

    // ---- top and bottom bars: workspaces left, Island centre, the rest right --------------------
    Component {
        id: horizontalLayout
        Item {
            anchors.fill: parent
            opacity: bar.stale ? Theme.staleOpacity : 1
            Behavior on opacity {
                enabled: bar.visible
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }

            Row {
                id: workspaceRow
                anchors { left: parent.left; leftMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                spacing: Theme.gap
                Repeater {
                    model: bar.pills
                    delegate: Rectangle {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        height: modelData.focused ? 10 : 8
                        width: modelData.focused ? 24 : 8
                        radius: height / 2
                        color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
                        border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
                        border.color: Theme.dim
                        Behavior on width {
                            enabled: bar.visible
                            NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
                        }
                    }
                }
            }
            // Disconnected glyph: instantiated only while stale (nothing at idle), after the workspaces.
            Loader {
                anchors { left: workspaceRow.right; leftMargin: Theme.gap; verticalCenter: parent.verticalCenter }
                active: bar.stale
                sourceComponent: Text {
                    color: Theme.accent
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: "⊘ " + I18n.tr("frontend.bar.disconnected")
                }
            }

            Island {
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                face: bar.island.face || "clock"
                reason: bar.island.reason || "default"
                slots: bar.bindings["island.main"] || ({})
                peekOutput: bar.screen ? bar.screen.name : ""
                // The user's binding decides what a slot does; an absent slot never reaches here.
                onActivated: slot => Store.act("input.dispatch", {component: "island.main", slot: slot})
            }

            Row {
                anchors { right: parent.right; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                spacing: Theme.pad
                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110
                    value: bar.daemonVolume
                    unavailable: !bar.audioUsable
                    fill: bar.audioMuted ? Theme.dim : Theme.accent
                    a11y: bar.volumeA11y
                    onMoved: v => bar.setVolume(v)
                    WheelHandler { enabled: bar.audioUsable; onWheel: event => bar.volumeStep(event.angleDelta.y) }
                }
                Repeater {
                    model: bar.modWidgets
                    delegate: ModLoader {
                        id: modW
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        url: modelData.url
                        // The hover or keyboard-focus peek (K35): the widget's `peek:<name>`, drawn by the Stage.
                        HoverHandler { id: modHover }
                        PeekSource {
                            target: modW
                            source: bar.modPeekOf(modW.modelData)
                            output: bar.screen ? bar.screen.name : ""
                            hovered: modHover.hovered
                            focused: modW.item !== null && modW.item.activeFocus === true
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: (bar.clock.hh ?? "--") + ":" + (bar.clock.mm ?? "--")
                }
                // Quick settings sit before the tray (K24); the panel is the daemon's runtime.ui.panel.
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    open: (Store.docs["runtime.ui"] || ({})).panel === "quick"
                    onClicked: Store.act("quick.toggle")
                }
                // The tray ends the row: its menus align to the bar's end (K23).
                Repeater {
                    model: bar.trayItems
                    delegate: trayIconDelegate
                }
            }
        }
    }

    // ---- left and right bars: the same items in one column. Wrapper items keep the column's
    // positioner away from anchors; the Island and the slider are turned to run along the bar.
    Component {
        id: verticalLayout
        Item {
            anchors.fill: parent
            opacity: bar.stale ? Theme.staleOpacity : 1
            Behavior on opacity {
                enabled: bar.visible
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }

            Column {
                id: workspaceCol
                anchors { top: parent.top; topMargin: Theme.pad; horizontalCenter: parent.horizontalCenter }
                spacing: Theme.gap
                Repeater {
                    model: bar.pills
                    delegate: Item {
                        required property var modelData
                        width: Theme.barH
                        height: modelData.focused ? 24 : 8
                        Rectangle {
                            anchors.centerIn: parent
                            width: modelData.focused ? 10 : 8
                            height: parent.height
                            radius: width / 2
                            color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
                            border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
                            border.color: Theme.dim
                        }
                    }
                }
            }
            // Disconnected glyph under the workspaces; the label does not fit a bar this thin.
            Loader {
                anchors { top: workspaceCol.bottom; topMargin: Theme.gap; horizontalCenter: parent.horizontalCenter }
                active: bar.stale
                sourceComponent: Text {
                    color: Theme.accent
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: "⊘"
                }
            }

            Island {
                anchors.centerIn: parent
                rotation: cfg.edge === "left" ? -90 : 90
                // Its peek is a side bar's too (I67): the Stage draws it beside the bar, aligned to the island.
                peekOutput: bar.screen ? bar.screen.name : ""
                face: bar.island.face || "clock"
                reason: bar.island.reason || "default"
                slots: bar.bindings["island.main"] || ({})
                onActivated: slot => Store.act("input.dispatch", {component: "island.main", slot: slot})
            }

            Column {
                anchors { bottom: parent.bottom; bottomMargin: Theme.pad; horizontalCenter: parent.horizontalCenter }
                spacing: Theme.gap
                Item {
                    width: Theme.barH
                    height: 110
                    Slider {
                        anchors.centerIn: parent
                        width: 110
                        rotation: -90
                        value: bar.daemonVolume
                        unavailable: !bar.audioUsable
                        fill: bar.audioMuted ? Theme.dim : Theme.accent
                        a11y: bar.volumeA11y
                        onMoved: v => bar.setVolume(v)
                        WheelHandler { enabled: bar.audioUsable; onWheel: event => bar.volumeStep(event.angleDelta.y) }
                    }
                }
                Repeater {
                    model: bar.modWidgets
                    delegate: Item {
                        id: vmod
                        required property var modelData
                        width: Theme.barH
                        height: Theme.barH
                        HoverHandler { id: vmodHover }
                        ModLoader {
                            id: vmodW
                            anchors.centerIn: parent
                            url: vmod.modelData.url
                        }
                        // The hover or keyboard-focus peek of a side bar's widget (K35, I67): drawn beside the bar.
                        PeekSource {
                            target: vmod
                            source: bar.modPeekOf(vmod.modelData)
                            output: bar.screen ? bar.screen.name : ""
                            hovered: vmodHover.hovered
                            focused: vmodW.item !== null && vmodW.item.activeFocus === true
                        }
                    }
                }
                Text {
                    width: Theme.barH
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: (bar.clock.hh ?? "--") + "\n" + (bar.clock.mm ?? "--")
                }
                QuickButton {
                    open: (Store.docs["runtime.ui"] || ({})).panel === "quick"
                    onClicked: Store.act("quick.toggle")
                }
                Repeater {
                    model: bar.trayItems
                    delegate: trayIconDelegate
                }
            }
        }
    }
}
