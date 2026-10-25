import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../core/mods.js" as Mods
import "../components"
import "../components/island"
import "../components/sidebar"

// One bar per output, on the edge that output's config names (bar.edge). bar.enabled false: no
// surface, no exclusive zone and no subscriptions held for it (Ma). Everything shown comes from
// Store; every click becomes an act/intent.
PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    // K59: this window's tile pair, shared by its reliefs (components/TileSheet.qml), and the pointer light's sensor.
    property var tileSheet: tilesLoader.item
    Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
    LightSense {}

    // This output's bar settings (config document, per-output entry wins).
    BarConfig { id: cfg; screen: bar.screen }
    readonly property bool vertical: cfg.vertical
    // The bar's edge, kept by Peeks for this output: the items' peeks ask for it, and a side bar's peek sits beside the bar (I67).
    readonly property string barEdge: cfg.edge
    onBarEdgeChanged: Peeks.setEdge(screen ? screen.name : "", barEdge)

    readonly property string origin: "qs:" + (screen ? screen.name : "?") + ":" + Math.floor(Math.random() * 1e6)
    // Veil: daemon away (or not yet current) -> keep last state, dim it, show the glyph.
    readonly property bool stale: !Store.live
    // Test only (frontend/test-sidebars.sh): the items' boxes are logged after each change. Off without the variable.
    readonly property bool geometryLog: Quickshell.env("KURASHI_BAR_GEOMETRY") === "1"

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
    // The quick button (K24), or with `sidebar.from_bar` the right sidebar on this output (W29): its open state and its click.
    readonly property var uiDoc: Store.docs["runtime.ui"] || ({})
    readonly property bool quickOpen: cfg.sidebarFromBar
        ? uiDoc.sidebar === "right" && (!uiDoc.sidebar_output || uiDoc.sidebar_output === (screen ? screen.name : ""))
        : uiDoc.panel === "quick"
    // I154: the sidebars' buttons at the bar's ends — open state per side on this output, and the click.
    readonly property string outName: screen ? screen.name : ""
    function sidebarOpen(side) {
        return uiDoc.sidebar === side && (!uiDoc.sidebar_output || uiDoc.sidebar_output === outName)
    }
    function toggleSidebar(side) { Store.act("sidebar.toggle", {side: side, output: outName}) }
    readonly property bool leftButton: cfg.sidebarButtons && cfg.leftSidebarTabs
    // The quick button already opens the right sidebar with `sidebar.from_bar`: no second button for it.
    readonly property bool rightButton: cfg.sidebarButtons && !cfg.sidebarFromBar
    function quickClicked() {
        if (cfg.sidebarFromBar) Store.act("sidebar.toggle", {side: "right", output: screen ? screen.name : ""})
        else Store.act("quick.toggle")
    }
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
    // A side bar's column holds this many tray icons (the vertical layout sets it, see there); a top or bottom bar holds all.
    property int trayFit: 0
    readonly property int trayVisible: vertical ? trayFit : 1000000
    // A tray menu is shown by the Stage on the output whose tray was clicked (shell.qml).
    signal trayMenuRequested(string id)
    readonly property real daemonVolume: audio.volume ?? 0
    readonly property string volumeA11y: !audioUsable ? I18n.tr("frontend.volume.unavailable")
        : (audioMuted ? I18n.tr("frontend.volume.muted")
            : I18n.tr("frontend.volume.level").replace("{pct}", Math.round(daemonVolume * 100)))
    // This output's workspace pills, or the "*" list when the daemon sends one for all outputs.
    // The windows of this output's active workspace (svc.workspaces `tasks`, session 9): one icon each, click focuses.
    readonly property var tasks: {
        var t = workspaces.tasks || {}
        var n = screen ? screen.name : ""
        return t[n] || t["*"] || []
    }
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
    // The leading items of a side bar's column that fit in `avail` px, `gap` apart (heights `hs`, top to bottom). When some
    // do not, a marker of `markH` follows the last one that does, so the marker is in the fit too. The end of the list hides first.
    function fitCount(hs, avail, gap, markH) {
        var total = 0
        for (var i = 0; i < hs.length; i++) total += hs[i] + (i > 0 ? gap : 0)
        if (total <= avail) return hs.length
        var used = 0
        for (var k = 0; k < hs.length; k++) {
            var next = used + (k > 0 ? gap : 0) + hs[k]
            if (next + gap + markH > avail) return k
            used = next
        }
        return hs.length
    }

    // One tray item, the same in both layouts. The bar's full thickness is its pointer target. A side bar hides the icons its
    // column has no room for (they come last, so they hide first).
    Component {
        id: trayIconDelegate
        TrayIcon {
            id: ticon
            required property var modelData
            required property int index
            visible: index < bar.trayVisible
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
            // W34: the item's menu grows out of it (IslandGeom's origins; top and bottom bars).
            AnchorReport { target: ticon; key: "tray:" + ticon.modelData.id; output: bar.outName; enabled: !bar.vertical }
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

    // The chrome decides how the bar's groups stand (K42, K45), from tokens only (rule 4):
    // - flat (`chrome.groups` false): one solid strip, the rows on it;
    // - groups with a shadow of either kind (keycap, soft): the groups float as blocks on the desk, the strip is clear;
    // - groups without a shadow (line): a terminal's status line — the strip, its inner edge ruled in the outline, and each
    //   group an outlined box with no fill behind its text.
    // Side bars keep their strip: their items are not grouped.
    readonly property bool lifted: Theme.shadowDy > 0 || Theme.softR > 0
    readonly property bool floating: Theme.groups && lifted && !vertical
    Rectangle {
        id: bg
        anchors.fill: parent
        color: bar.floating ? "transparent" : Theme.surfaceAlpha
        // The strip's inner edge, ruled in the outline (line chrome; 0 px under flat). While the island's shape is out on
        // this bar (W30, IslandGeom.openL/R) the rule is left out under the shape's box, which draws the rule there itself,
        // in step with the card: round the hanging card's fillets into its sides, never under a translucent card. The
        // opening stands still while the card morphs, so the two surfaces never disagree mid-morph.
        readonly property bool opened: !bar.vertical && IslandGeom.openR > IslandGeom.openL
            && IslandGeom.takenOn !== "" && IslandGeom.takenOn === (bar.screen ? bar.screen.name : "")
        // Row 363 (W34): an open sidebar at rest on this edge leaves the rule out over the span its column covers
        // (SidebarGeom), so the column's outline runs round its fillet into the rule's end — one sheet, no seam.
        readonly property var sideOpen: {
            var o = SidebarGeom.openingOf(bar.screen ? bar.screen.name : "")
            return o && o.edge === cfg.edge ? o : null
        }
        // The rule as segments along the edge: everything but the island's opening and the sidebar's span.
        readonly property real ruleLen: bar.vertical ? height : width
        readonly property var ruleSegs: {
            var gaps = []
            if (opened) gaps.push([Math.max(0, width / 2 + IslandGeom.openL), width / 2 + IslandGeom.openR])
            if (sideOpen) gaps.push([Math.max(0, sideOpen.from), Math.min(ruleLen, sideOpen.to)])
            gaps.sort(function (x, y) { return x[0] - y[0] })
            var segs = [], at = 0
            for (var i = 0; i < gaps.length; i++) {
                if (gaps[i][0] > at) segs.push([at, gaps[i][0]])
                at = Math.max(at, gaps[i][1])
            }
            if (at < ruleLen) segs.push([at, ruleLen])
            return segs
        }
        // K59: the strip's material, under its rules (flat chrome; floating groups stand on their own blocks).
        Loader {
            anchors.fill: parent
            active: !bar.floating && Theme.texShell
            sourceComponent: Relief { anchors.fill: parent }
        }
        // K62: with a pen in effect the rule is drawn by the pen, as one open line (two, either side of the island's
        // opening); the opening and the line's ends are the rectangles' below.
        Loader {
            id: rulePen
            anchors.fill: parent
            active: Theme.penOutline && !bar.floating && Theme.outlineW > 0
            sourceComponent: PenOutline {
                readonly property real ow: Theme.outlineW
                readonly property real cy: cfg.edge === "top" ? height - ow / 2 : ow / 2
                readonly property real cx: cfg.edge === "left" ? width - ow / 2 : ow / 2
                color: Theme.outlineColor
                lineWidth: ow
                seed: bar.vertical ? 0xB4A2 : 0xB4A1
                paths: bg.ruleSegs.map(function (g) {
                    return bar.vertical ? { points: [{ x: cx, y: g[0] }, { x: cx, y: g[1] }], closed: false }
                                        : { points: [{ x: g[0], y: cy }, { x: g[1], y: cy }], closed: false }
                })
            }
        }
        Repeater {
            model: !bar.floating && Theme.outlineW > 0 && !rulePen.active ? bg.ruleSegs : []
            Rectangle {
                required property var modelData
                color: Theme.outlineColor
                x: bar.vertical ? (cfg.edge === "left" ? bg.width - width : 0) : modelData[0]
                y: bar.vertical ? modelData[0] : (cfg.edge === "top" ? bg.height - height : 0)
                width: bar.vertical ? Theme.outlineW : Math.max(0, modelData[1] - modelData[0])
                height: bar.vertical ? Math.max(0, modelData[1] - modelData[0]) : Theme.outlineW
            }
        }
    }
    // K47 (W23-system, docs/ux/power.md): the keyboard layout's short name (svc.keyboard), shown only while the compositor
    // names more than one layout; a click switches to the next (`keyboard.next`). Its document is watched
    // while the chip exists, i.e. while the bar is shown (the compositor stream behind it is refcounted, Ma).
    component KeyboardChip: Item {
        id: kb
        Watch { doc: "svc.keyboard" }
        readonly property var d: Store.docs["svc.keyboard"] || ({})
        readonly property var layouts: d.layouts || []
        readonly property var cur: layouts.length > 0 ? layouts[Math.max(0, Math.min(layouts.length - 1, Number(d.current || 0)))] : null
        visible: layouts.length > 1
        width: visible ? kbText.implicitWidth + 2 * Theme.xs : 0
        height: Theme.barH - 12
        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("power.bar.layout").replace("{name}", kb.cur ? String(kb.cur.name) : "")
        Rectangle {
            anchors.fill: parent
            radius: Theme.rSm
            color: kbHover.hovered ? Theme.containerHigh : "transparent"
        }
        Text {
            id: kbText
            anchors.centerIn: parent
            color: Theme.fg
            font.pixelSize: Theme.fsCaption
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: kb.cur ? String(kb.cur.short).toUpperCase() : ""
        }
        HoverHandler { id: kbHover }
        TapHandler { onTapped: Store.act("keyboard.next") }
    }
    // K47: a recording runs (svc.recorder) — a red dot and its label; a click stops it (`recorder.stop`). Nothing at all while
    // nothing records; the dot does not blink (no animation, Ma).
    component RecordDot: Item {
        id: rd
        Watch { doc: "svc.recorder" }
        readonly property bool recording: (Store.docs["svc.recorder"] || ({})).recording === true
        visible: recording
        width: visible ? dotRow.implicitWidth + 2 * Theme.xs : 0
        height: Theme.barH - 12
        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("power.bar.recording")
        Row {
            id: dotRow
            anchors.centerIn: parent
            spacing: Theme.xs
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: Theme.error
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.error
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("power.bar.rec")
            }
        }
        TapHandler { onTapped: Store.act("recorder.stop") }
    }

    // A group's block behind a row of the bar (chromes with groups): the row's box plus `Theme.gap` around it, the face
    // centred on the bar. Under flat chrome nothing is drawn and nothing moves (the rows keep their places). The soft
    // shadow is a short one: the bar's window ends a few px under the block.
    component Group: Block {
        required property Item around
        readonly property real padX: Theme.gap + 2
        visible: Theme.groups && around.visible && around.width > 0
        x: around.x - padX
        y: (parent.height - Theme.shadowDy - (Theme.barH - 8)) / 2
        width: around.width + 2 * padX
        height: Theme.barH - 8 + Theme.shadowDy
        radius: Theme.rFull
        ringScale: 0.5
        softScale: 0.3
        // (An inline component does not see the bar's ids: `lifted` again, from the tokens.)
        fill: Theme.shadowDy > 0 || Theme.softR > 0 ? Theme.surfaceAlpha : "transparent"
    }
    // How far a group's row sits in from the bar's end (the group's padding); 0 under flat chrome.
    readonly property real groupInset: Theme.groups ? Theme.gap + 2 + Theme.xs : 0

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

    // A workspace in a top or bottom bar. Flat chrome: a dot, the focused one a wider accent bar. Chromes with groups: a
    // small numbered key — focused lit in the accent, occupied on the container (an outlined box under line chrome),
    // empty on the ring (keycap) or bare — that sinks, shrinks or flashes while pressed.
    // A click focuses the workspace (niri's own action through the daemon).
    Component {
        id: dotPill
        Rectangle {
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            height: modelData.focused ? 10 : 8
            width: modelData.focused ? 24 : 8
            radius: height / 2
            color: modelData.focused ? Theme.accent : (modelData.occupied ? Theme.fg : "transparent")
            border.width: (!modelData.focused && !modelData.occupied) ? 1 : 0
            border.color: Theme.dim
            Behavior on width {
                enabled: bar.visible
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
        }
    }
    Component {
        id: keyPill
        Block {
            id: kp
            required property var modelData
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: Theme.shadowDy / 2
            width: modelData.focused ? 34 : 22
            height: 20 + Theme.shadowDy
            radius: Theme.rFull
            ringScale: 0
            softScale: 0
            pressed: wsTap.pressed
            fill: modelData.focused ? Theme.accent
                : (modelData.occupied ? (bar.lifted ? Theme.containerHigh : "transparent")
                    : (Theme.ringW > 0 ? Theme.ring : "transparent"))
            opacity: modelData.focused || modelData.occupied ? 1 : 0.7
            Behavior on width {
                enabled: bar.visible && Theme.springOn
                NumberAnimation { duration: Theme.stdMs + 80; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot }
            }
            Text {
                anchors.centerIn: parent
                color: kp.modelData.focused ? Theme.fgOnAccent : (kp.modelData.occupied ? Theme.fg : Theme.dim)
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: kp.modelData.idx ?? ""
            }
            TapHandler { id: wsTap; onTapped: Store.act("workspace.focus", {id: kp.modelData.id}) }
        }
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

            Group { id: wsGroup; around: workspaceRow; AnchorReport { target: wsGroup; key: "group:workspaces"; output: bar.outName; enabled: wsGroup.visible } }
            Row {
                id: workspaceRow
                anchors { left: parent.left; leftMargin: Theme.pad + bar.groupInset; verticalCenter: parent.verticalCenter }
                anchors.verticalCenterOffset: -Theme.shadowDy / 2
                spacing: Theme.groups ? Theme.xs + 1 : Theme.gap
                SidebarButton {
                    visible: bar.leftButton
                    anchors.verticalCenter: parent.verticalCenter
                    side: "left"
                    open: bar.sidebarOpen("left")
                    onClicked: bar.toggleSidebar("left")
                }
                Repeater {
                    model: bar.pills
                    delegate: Theme.groups ? keyPill : dotPill
                }
            }
            // The window list: after the workspaces, in a group of its own (keycap) — the focused window lit.
            Group { id: taskGroup; around: taskRow; AnchorReport { target: taskGroup; key: "group:tasks"; output: bar.outName; enabled: taskGroup.visible } }
            Row {
                id: taskRow
                visible: bar.tasks.length > 0
                anchors { left: workspaceRow.right; leftMargin: Theme.pad + 2 * bar.groupInset; verticalCenter: parent.verticalCenter }
                anchors.verticalCenterOffset: -Theme.shadowDy / 2
                spacing: Theme.xs
                Repeater {
                    model: bar.tasks.slice(0, 12)
                    delegate: Rectangle {
                        id: task
                        required property var modelData
                        readonly property var entry: DesktopEntries.heuristicLookup(modelData.app_id)
                        readonly property string src: entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.barH - 12
                        height: width
                        radius: Theme.groups ? Math.min(width / 2, Theme.rFull) : Theme.rSm
                        color: modelData.focused ? Theme.selected : (taskHover.hovered ? Theme.containerHigh : "transparent")
                        border.width: modelData.focused ? Theme.outlineW : 0
                        border.color: Theme.outlineColor
                        Accessible.role: Accessible.Button
                        Accessible.name: entry ? entry.name : modelData.app_id
                        Image {
                            id: taskImg
                            anchors.centerIn: parent
                            width: parent.width - 8
                            height: width
                            source: task.src
                            sourceSize: Qt.size(48, 48)
                            asynchronous: true
                            visible: task.src !== "" && status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !taskImg.visible
                            color: Theme.fg
                            font.pixelSize: Theme.fsCaption
                            font.weight: Theme.wBold
                            font.family: Theme.fam(text, Theme.families)
                            text: (task.modelData.app_id || "?").charAt(0).toUpperCase()
                        }
                        // The focused window's mark under its icon, so focus is not colour alone.
                        Rectangle {
                            visible: task.modelData.focused
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 1 }
                            width: 10; height: 3; radius: 1.5
                            color: Theme.accent
                        }
                        HoverHandler { id: taskHover }
                        TapHandler { onTapped: Store.act("window.focus", {id: task.modelData.id}) }
                    }
                }
            }
            // Disconnected glyph: instantiated only while stale (nothing at idle), after the workspaces.
            Loader {
                anchors { left: taskRow.visible ? taskRow.right : workspaceRow.right; leftMargin: Theme.gap; verticalCenter: parent.verticalCenter }
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

            Group { id: rightGroup; around: rightRow; AnchorReport { target: rightGroup; key: "group:right"; output: bar.outName; enabled: rightGroup.visible } }
            Row {
                id: rightRow
                anchors { right: parent.right; rightMargin: Theme.pad + bar.groupInset; verticalCenter: parent.verticalCenter }
                anchors.verticalCenterOffset: -Theme.shadowDy / 2
                spacing: Theme.pad
                // The volume's icon (chromes with groups): a click mutes, as the media key does.
                Icon {
                    visible: Theme.groups && bar.audioUsable
                    anchors.verticalCenter: parent.verticalCenter
                    name: bar.audioMuted ? "volume_off" : "volume_up"
                    glyph: bar.audioMuted ? "🔇" : "🔊"
                    filled: true
                    color: Theme.fg
                    TapHandler { onTapped: Store.act("audio.mute.toggle") }
                }
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
                        // W34: the mod's panel grows out of its widget (IslandGeom's origins).
                        AnchorReport { target: modW; key: "mod:" + modW.modelData.mod + ":" + String(modW.modelData.provide).substring(7); output: bar.outName }
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
                RecordDot { anchors.verticalCenter: parent.verticalCenter }
                KeyboardChip { anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: (bar.clock.hh ?? "--") + ":" + (bar.clock.mm ?? "--")
                }
                // Quick settings sit before the tray (K24); the panel is the daemon's runtime.ui.panel.
                QuickButton {
                    anchors.verticalCenter: parent.verticalCenter
                    open: bar.quickOpen
                    onClicked: bar.quickClicked()
                }
                // The tray ends the row: its menus align to the bar's end (K23).
                Repeater {
                    model: bar.trayItems
                    delegate: trayIconDelegate
                }
                // I154: the right sidebar's button at the very end.
                SidebarButton {
                    visible: bar.rightButton
                    anchors.verticalCenter: parent.verticalCenter
                    side: "right"
                    open: bar.sidebarOpen("right")
                    onClicked: bar.toggleSidebar("right")
                }
            }
        }
    }

    // ---- left and right bars: the same items in one column. Top to bottom: the workspaces, the Island at the centre (a
    // column, see Island.qml), and below it the volume slider, the mod widgets, the clock, the quick settings and the tray,
    // in the horizontal right row's order and spacing (I85). Each widget takes the bar's 36 px width: text is not turned,
    // the values are shortened and their full text is the accessible name. The bottom column holds the leading items that
    // fit between the island and the bar's end; the rest hide from the end, with the count "+N". Wrapper items keep the
    // column's positioner away from anchors.
    Component {
        id: verticalLayout
        Item {
            id: vlayout
            anchors.fill: parent
            opacity: bar.stale ? Theme.staleOpacity : 1
            Behavior on opacity {
                enabled: bar.visible
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }

            // The bottom column's slots, top to bottom: the slider, each mod widget (its own height once measured, else a
            // default; clipped to the slot at the bar's edge), the clock, the quick button, each tray icon.
            readonly property int sliderH: 110
            // A mod slot's height until its widget has been measured. Small on purpose: an unmeasured widget is then loaded
            // and measured; a large default would keep a widget that does not fit unloaded, so it would never be measured.
            readonly property int modSlotH: Theme.barH
            readonly property int modN: bar.modWidgets.length
            readonly property int trayN: bar.trayItems.length
            // The mod slots' heights, by mod index, as each widget reports them (see setModSlot): a plain list, so the
            // fit never reads the Repeater (a binding that creates delegates while it is read is a loop).
            property var modSlotsH: []
            function modSlotOf(i) { var h = modSlotsH[i]; return h > 0 ? h : modSlotH }
            function setModSlot(i, h) {
                if (modSlotsH[i] === h) return
                var a = modSlotsH.slice()
                a[i] = h
                modSlotsH = a
            }
            // The clock's two lines, measured on a text that does not change: a hidden Text is not laid out, so its own
            // implicit height would follow the fit it feeds (a binding loop).
            TextMetrics { id: clockM; text: "00"; font.pixelSize: Theme.fs; font.family: Theme.fam(text, Theme.families) }
            readonly property real clockH: 2 * clockM.height
            readonly property var slotH: {
                var h = [sliderH]
                for (var i = 0; i < modN; i++) h.push(modSlotOf(i))
                h.push(clockH)
                h.push(Theme.barH)
                for (var j = 0; j < trayN; j++) h.push(Theme.barH)
                return h
            }
            // The room between the island's lower edge (with a gap) and the bar's end (with the bottom margin).
            // The right sidebar's button sits below the column, at the bar's end (I154): its room is not the column's.
            readonly property real endButtonH: bar.rightButton ? Theme.barH + Theme.pad : 0
            readonly property real columnAvail: height / 2 - isl.height / 2 - Theme.gap - Theme.pad - endButtonH
            // The marker's height is measured on a fixed text: the marker's own text depends on the fit (a loop otherwise).
            TextMetrics { id: markM; text: "+0"; font.pixelSize: Theme.fsCaption; font.family: Theme.fam(text, Theme.families) }
            readonly property int fit: bar.fitCount(slotH, columnAvail, Theme.pad, markM.height)
            readonly property int hiddenN: slotH.length - fit
            // The tray icons this column holds: the slots after the slider, the mods, the clock and the quick button.
            Binding {
                target: bar
                property: "trayFit"
                value: Math.max(0, Math.min(vlayout.trayN, vlayout.fit - 3 - vlayout.modN))
            }

            Column {
                id: workspaceCol
                anchors { top: parent.top; topMargin: Theme.pad; horizontalCenter: parent.horizontalCenter }
                spacing: Theme.gap
                // I154: the left sidebar's button heads the column.
                SidebarButton {
                    id: sbLeftV
                    visible: bar.leftButton
                    side: "left"
                    open: bar.sidebarOpen("left")
                    onClicked: bar.toggleSidebar("left")
                }
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
                id: isl
                anchors.centerIn: parent
                // A side bar's island is a column, not a turned row (I85); its peek is a side bar's too (I67): the Stage draws
                // it beside the bar, aligned to the island.
                vertical: true
                peekOutput: bar.screen ? bar.screen.name : ""
                face: bar.island.face || "clock"
                reason: bar.island.reason || "default"
                slots: bar.bindings["island.main"] || ({})
                onActivated: slot => Store.act("input.dispatch", {component: "island.main", slot: slot})
            }

            SidebarButton {
                id: sbRightV
                visible: bar.rightButton
                anchors { bottom: parent.bottom; bottomMargin: Theme.pad; horizontalCenter: parent.horizontalCenter }
                side: "right"
                open: bar.sidebarOpen("right")
                onClicked: bar.toggleSidebar("right")
            }
            Column {
                id: stack
                anchors { bottom: parent.bottom; bottomMargin: Theme.pad + vlayout.endButtonH; horizontalCenter: parent.horizontalCenter }
                spacing: Theme.pad
                Item {
                    visible: vlayout.fit >= 1
                    width: Theme.barH
                    height: vlayout.sliderH
                    Slider {
                        id: sliderV
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
                    id: modRep
                    model: bar.modWidgets
                    delegate: Item {
                        id: vmod
                        required property var modelData
                        required property int index
                        // Past the column's end the widget is not loaded either (ModLoader's gate, Ma).
                        visible: vlayout.fit > 1 + index
                        width: Theme.barH
                        // The slot is the widget's own height once measured (kept while it is unloaded, so the fit does not flip).
                        height: vlayout.modSlotOf(index)
                        clip: true
                        readonly property var widgetItem: vmodW.item
                        function measure() {
                            if (vmodW.item && ("vertical" in vmodW.item) && vmodW.item.implicitHeight > 0)
                                vlayout.setModSlot(index, Math.ceil(vmodW.item.implicitHeight))
                        }
                        HoverHandler { id: vmodHover }
                        ModLoader {
                            id: vmodW
                            anchors.centerIn: parent
                            url: vmod.modelData.url
                            shown: vmod.visible
                        }
                        // Measured on the next turn: a widget loaded by the fit (its visibility) must not change the fit in the same pass.
                        Connections { target: vmodW; function onItemChanged() { Qt.callLater(vmod.measure) } }
                        Connections { target: vmodW.item; ignoreUnknownSignals: true; function onImplicitHeightChanged() { Qt.callLater(vmod.measure) } }
                        // A widget that declares `vertical` is told that its bar is a side one; one that does not is drawn as it is
                        // and clipped to the slot (ModLoader passes nothing else).
                        Binding {
                            target: vmodW.item
                            property: "vertical"
                            value: true
                            when: vmodW.item !== null && vmodW.item !== undefined && ("vertical" in vmodW.item)
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
                    id: clockT
                    visible: vlayout.fit > 1 + vlayout.modN
                    width: Theme.barH
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: (bar.clock.hh ?? "--") + "\n" + (bar.clock.mm ?? "--")
                }
                QuickButton {
                    id: quickB
                    visible: vlayout.fit > 2 + vlayout.modN
                    open: bar.quickOpen
                    onClicked: bar.quickClicked()
                }
                Repeater {
                    id: trayRep
                    model: bar.trayItems
                    delegate: trayIconDelegate
                }
                // The count of the items the column has no room for (see fit); it follows the last item that is shown.
                Text {
                    id: hiddenT
                    visible: vlayout.hiddenN > 0
                    width: Theme.barH
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: "+" + vlayout.hiddenN
                    Accessible.role: Accessible.StaticText
                    Accessible.name: I18n.tr("frontend.bar.hidden").replace("{n}", vlayout.hiddenN)
                }
            }

            // Test only (KURASHI_BAR_GEOMETRY=1, frontend/test-sidebars.sh): the boxes of what this bar draws, logged a moment
            // after each change, so the test asserts the layout from the items' geometry. Without the variable: no timer, no log.
            Timer {
                id: geoT
                interval: 300
                onTriggered: vlayout.logGeometry()
            }
            function requestGeometry() { if (bar.geometryLog) geoT.restart() }
            onWidthChanged: requestGeometry()
            onHeightChanged: requestGeometry()
            onFitChanged: requestGeometry()
            Component.onCompleted: requestGeometry()
            Connections {
                target: Store
                enabled: bar.geometryLog
                function onDocsChanged() { vlayout.requestGeometry() }
            }
            // A box in the bar's window: a rotated item (the slider) is measured by its four corners, as it is drawn.
            function boxOf(it) {
                var cs = bar.contentItem
                var a = it.mapToItem(cs, 0, 0), b = it.mapToItem(cs, it.width, 0)
                var c = it.mapToItem(cs, 0, it.height), d = it.mapToItem(cs, it.width, it.height)
                return [Math.min(a.x, b.x, c.x, d.x), Math.min(a.y, b.y, c.y, d.y),
                    Math.max(a.x, b.x, c.x, d.x), Math.max(a.y, b.y, c.y, d.y)].map(v => Math.round(v)).join(" ")
            }
            function shownOf(it) {
                if (!it) return false
                for (var p = it; p; p = p.parent) if (!p.visible) return false
                return true
            }
            function logGeometry() {
                var out = ["BARGEO bar 0 0 " + Math.round(bar.width) + " " + Math.round(bar.height)]
                out.push("BARGEO fit " + fit + " hidden " + hiddenN + " trays " + trayN + " shown " + bar.trayFit)
                function add(name, it) { if (shownOf(it)) out.push("BARGEO " + name + " " + boxOf(it)) }
                add("workspaces", workspaceCol)
                add("island", isl)
                add("slider", sliderV)
                add("clock", clockT)
                add("quick", quickB)
                add("more", hiddenT)
                add("sidebar-left", sbLeftV)
                add("sidebar-right", sbRightV)
                for (var i = 0; i < modRep.count; i++) {
                    var d = modRep.itemAt(i)
                    if (!d) continue
                    add("slot-" + d.modelData.mod, d)
                    add("widget-" + d.modelData.mod, d.widgetItem)
                }
                for (var j = 0; j < trayRep.count; j++) add("tray" + j, trayRep.itemAt(j))
                for (var k = 0; k < out.length; k++) console.log(out[k])
            }
        }
    }
}
