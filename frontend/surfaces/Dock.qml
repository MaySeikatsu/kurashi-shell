import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// The app dock (K51, docs/ux/dock.md) of one output: pinned apps (`dock.pinned`, desktop ids) then the running ones
// grouped by app id, at `dock.edge`, while `dock.enabled` is on for this output. A pure view: the windows come from
// `svc.workspaces.windows`, every press is an action (`window.focus`, `window.close`, `launcher.launch`) or one config
// write (`dock.pinned`). Copied where others solved it: the click rule (none → launch, focused → next, else focus) and
// the four-dot cap from DMS `Modules/Dock/DockAppButton.qml`; the hover truth (one "pointer inside" from every part,
// timers that re-check when they fire) from Noctalia `Modules/Dock/Dock.qml`; "shown while the desk is empty" from ii
// `modules/ii/dock/Dock.qml`; the 4 px edge window with a 2 px zone from our web dock (K40).
// Ma: no surface while off; hidden = the edge window only (the dock window unmapped); nothing animates idle — the
// slide and the hover magnify run only on a change, timers only while the pointer is on the dock or its edge.
Scope {
    id: dk
    required property var modelData

    BarConfig { id: cfg; screen: dk.modelData }
    readonly property bool wanted: cfg.valueOf("dock.enabled", false) === true

    LazyLoader {
        active: dk.wanted
        Scope {
            id: dock
            readonly property var scr: dk.modelData
            readonly property string outName: scr ? scr.name : ""
            readonly property string edge: {
                var e = cfg.valueOf("dock.edge", "bottom")
                return e === "left" || e === "right" ? e : "bottom"
            }
            readonly property bool horiz: edge === "bottom"
            readonly property bool autohide: cfg.valueOf("dock.autohide", true) === true
            readonly property bool showRunning: cfg.valueOf("dock.show_running", true) === true
            readonly property var pinnedEntry: cfg.entry("dock.pinned")
            readonly property var pinned: {
                var p = cfg.valueOf("dock.pinned", [])
                return Array.isArray(p) ? p.filter(function (s) { return typeof s === "string" && s !== "" }) : []
            }
            // A forced list cannot be changed here: the menu says by whom (Shōjiki).
            readonly property string pinForcedBy: pinnedEntry && pinnedEntry.forced_by ? String(pinnedEntry.forced_by) : ""
            readonly property int wantIcon: {
                var s = cfg.valueOf("dock.icon_size", 44)
                return typeof s === "number" ? Math.max(24, Math.min(96, Math.round(s))) : 44
            }

            Watch { doc: "svc.workspaces" }
            readonly property var ws: Store.docs["svc.workspaces"] || ({})
            readonly property var windows: Array.isArray(ws.windows) ? ws.windows : []
            // The desk is empty (ii): this output's active workspace holds no window — nothing to cover.
            readonly property bool emptyDesk: {
                var t = ws.tasks
                if (!t) return false
                var l = t[outName] || t["*"]
                return Array.isArray(l) && l.length === 0
            }

            // ---- the apps ----
            // DesktopEntries fills in asynchronously; its change re-runs the grouping.
            property int entriesRev: 0
            Connections {
                target: DesktopEntries
                function onApplicationsChanged() { dock.entriesRev++ }
            }
            function norm(s) { return String(s || "").toLowerCase().replace(/\.desktop$/, "") }
            // key → {key, id, entry, name, pinned, windows}; `keys` is the order, with "|" between pinned and running.
            readonly property var groups: {
                var rev = entriesRev
                var out = {}, order = [], running = []
                for (var i = 0; i < pinned.length; i++) {
                    var id = pinned[i], k = norm(id)
                    if (out[k]) continue
                    var e = DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id)
                    out[k] = { key: k, id: e ? e.id : id, entry: e, name: e ? e.name : id, pinned: true, windows: [] }
                    // Windows find the pin by their entry's id too (a pin found heuristically has another id).
                    if (e && !out[norm(e.id)]) out[norm(e.id)] = out[k]
                    order.push(k)
                }
                for (var j = 0; j < windows.length; j++) {
                    var w = windows[j]
                    var appId = String(w.app_id || "")
                    var en = appId !== "" ? DesktopEntries.heuristicLookup(appId) : null
                    var key = en ? norm(en.id) : (appId !== "" ? norm(appId) : "?" + w.id)
                    var g = out[key] || out[norm(appId)]
                    if (!g) {
                        if (!showRunning) continue
                        g = { key: key, id: en ? en.id : appId, entry: en, name: en ? en.name : (appId || "?"),
                              pinned: false, windows: [] }
                        out[key] = g
                        running.push(key)
                    }
                    g.windows.push(w)
                }
                var keys = order.slice()
                if (order.length > 0 && running.length > 0) keys.push("|")
                keys = keys.concat(running)
                if (keys.length === 0) keys.push("+")      // the empty state: one tile that opens the launcher
                return { map: out, keys: keys }
            }
            // The model changes only when the order does: a focus change must not remake the tiles.
            property var keys: []
            readonly property string keysJson: JSON.stringify(groups.keys)
            onKeysJsonChanged: keys = JSON.parse(keysJson)
            Component.onCompleted: { keys = JSON.parse(keysJson); if (wantShown) everShown = true }

            // The last window seen focused per app: a click brings that one back (GNOME, macOS).
            property var lastFocus: ({})
            onWindowsChanged: {
                for (var i = 0; i < windows.length; i++) if (windows[i].focused) {
                    var en = DesktopEntries.heuristicLookup(String(windows[i].app_id || ""))
                    lastFocus[en ? norm(en.id) : norm(windows[i].app_id)] = windows[i].id
                }
            }

            // ---- actions ----
            function launch(g) {
                if (!g || !g.entry) { flash(g ? g.key : "", I18n.tr("dock.error.no_entry")); return }
                var key = g.key
                Store.act("launcher.launch", { id: g.entry.id }, function (done, err) {
                    if (err) dock.flash(key, I18n.tr("dock.error.launch"))
                })
            }
            function activate(g) {
                if (!g) return
                if (menuOpen) { menuKey = ""; return }
                if (g.key === "+") { Store.act("launcher.toggle", {}); return }
                var list = g.windows
                if (list.length === 0) { launch(g); return }
                var fi = -1
                for (var i = 0; i < list.length; i++) if (list[i].focused) fi = i
                var target = null
                if (fi >= 0) target = list[(fi + 1) % list.length]
                else {
                    var last = lastFocus[g.key]
                    for (var j = 0; j < list.length; j++) if (list[j].id === last) target = list[j]
                    if (!target) target = list[0]
                }
                Store.act("window.focus", { id: target.id })
            }
            function setPinned(g, pin) {
                var list = pinned.filter(function (p) { return norm(p) !== g.key })
                if (pin) list.push(g.id)
                menuError = ""
                Store.apply([{ set: "dock.pinned", value: list }], function (errors) {
                    if (errors) dock.menuError = I18n.tr("dock.error.write")
                    else dock.menuKey = ""
                })
            }
            function closeAll(g) {
                for (var i = 0; i < g.windows.length; i++) Store.act("window.close", { id: g.windows[i].id })
                menuKey = ""
            }

            // A short note on a tile (a failed launch): shown in its tooltip for a while.
            property string noteKey: ""
            property string noteText: ""
            function flash(key, text) { noteKey = key; noteText = text; noteTimer.restart() }
            Timer { id: noteTimer; interval: 2500; onTriggered: { dock.noteKey = ""; dock.noteText = "" } }

            // ---- sizes ----
            readonly property int alongMax: scr ? (horiz ? scr.width : scr.height) - 4 * Theme.gap : 800
            readonly property int bodyPad: Theme.gap
            readonly property int spacing: Theme.xs + 2
            readonly property int sepW: Theme.xs * 2 + 2
            readonly property int dotRoom: 6
            readonly property int tileCount: keys.filter(function (k) { return k !== "|" }).length
            readonly property bool hasSep: keys.indexOf("|") >= 0
            // Tiles shrink to fit the output (min 24 px); past that the list scrolls.
            readonly property int icon: {
                var room = alongMax - 2 * bodyPad - (hasSep ? sepW + spacing : 0)
                var fit = Math.floor(room / Math.max(1, tileCount) - spacing - (horiz ? 0 : Theme.shadowDy))
                return Math.max(24, Math.min(wantIcon, fit))
            }
            // A tile's hard shadow (keycap) falls down: across a bottom dock, along a side one.
            readonly property int tileAlong: horiz ? icon : icon + Theme.shadowDy
            readonly property int cellAcross: horiz ? icon + Theme.shadowDy + dotRoom : icon + dotRoom + 2
            readonly property int listAlong: tileCount * (tileAlong + spacing) - spacing + (hasSep ? sepW + spacing : 0)
            readonly property int bodyAlong: Math.min(alongMax, listAlong + 2 * bodyPad)
            // The body Block: its hard shadow (keycap) adds to its height only.
            readonly property int bodyW: horiz ? bodyAlong : cellAcross + 2 * bodyPad
            readonly property int bodyH: (horiz ? cellAcross + 2 * bodyPad : bodyAlong) + Theme.shadowDy
            readonly property int bodyAcross: horiz ? bodyH : bodyW
            // Room for the soft shadow round the body, and the gap to the screen edge.
            readonly property int room: Theme.softR > 0 ? Math.ceil(Theme.softR + Math.abs(Theme.softDy)) : 3
            readonly property int edgeGap: Math.max(Theme.gap, room)
            readonly property int winW: horiz ? bodyAlong + 2 * room : bodyAcross + room + edgeGap
            readonly property int winH: horiz ? bodyAcross + room + edgeGap : bodyH + 2 * room

            // ---- hover, reveal, hide ----
            property bool edgeIn: false
            property bool bodyIn: false
            readonly property bool menuOpen: menuKey !== ""
            readonly property bool pointerIn: edgeIn || bodyIn || menuOpen
            readonly property bool holdOpen: !autohide || emptyDesk || menuOpen
            property bool revealed: false
            readonly property bool wantShown: holdOpen || revealed
            onPointerInChanged: {
                if (pointerIn) {
                    hideTimer.stop()
                    if (shownAmt > 0) revealed = true
                    else if (edgeIn) revealTimer.restart()
                } else {
                    revealTimer.stop()
                    if (revealed) hideTimer.restart()
                }
            }
            onEdgeInChanged: if (edgeIn && !wantShown) revealTimer.restart()
            Timer { id: revealTimer; interval: 250; onTriggered: if (dock.edgeIn) dock.revealed = true }
            Timer { id: hideTimer; interval: 400; onTriggered: if (!dock.pointerIn) dock.revealed = false }
            onAutohideChanged: { revealed = false; hideTimer.stop(); revealTimer.stop() }

            // 0 = hidden (the window unmapped), 1 = shown; it moves only on a change.
            property real shownAmt: wantShown ? 1 : 0
            Behavior on shownAmt {
                enabled: Theme.springOn
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }

            // ---- menu and tooltip state ----
            property string menuKey: ""
            property string menuError: ""
            property var menuTile: null
            property string tipKey: ""
            property var tipTile: null
            function openMenu(key, tile) {
                tipKey = ""; menuError = ""; menuCurrent = 0; menuTile = tile
                var p = tile.mapToItem(null, 0, 0)
                menuAt = Qt.rect(winOrigin().x + p.x, winOrigin().y + p.y, tile.width, tile.height)
                menuKey = key
            }
            // The tile's box on the output, for the menu: the dock window's place is the compositor's (centred on its
            // edge, in the area the bar leaves), so it is worked out the same way here.
            property rect menuAt: Qt.rect(0, 0, 0, 0)
            function winOrigin() {
                var w = scr ? scr.width : 0, h = scr ? scr.height : 0
                var top = cfg.atTop ? Theme.barH : 0, bottom = cfg.atBottom ? Theme.barH : 0
                var left = cfg.enabled && cfg.edge === "left" ? Theme.barH : 0, right = cfg.atRight ? Theme.barH : 0
                if (horiz) return Qt.point((w - winW) / 2, h - bottom - winH)
                var y = top + (h - top - bottom - winH) / 2
                return Qt.point(edge === "left" ? left : w - right - winW, y)
            }
            readonly property var menuGroup: menuKey !== "" ? (groups.map[menuKey] || null) : null
            // The rows: {text, on (enabled), run}, built from the app the menu is about.
            readonly property var menuRows: {
                var g = menuGroup
                if (!g) return []
                var r = []
                r.push({ text: g.pinned ? I18n.tr("dock.menu.unpin") : I18n.tr("dock.menu.pin"),
                         on: pinForcedBy === "" && g.id !== "", run: function () { dock.setPinned(g, !g.pinned) } })
                r.push({ text: I18n.tr("dock.menu.new_window"), on: !!g.entry,
                         run: function () { dock.menuKey = ""; dock.launch(g) } })
                if (g.windows.length === 1)
                    r.push({ text: I18n.tr("dock.menu.close"), on: true, run: function () { dock.closeAll(g) } })
                else if (g.windows.length > 1)
                    r.push({ text: I18n.tr("dock.menu.close_all").replace("{n}", g.windows.length), on: true,
                             run: function () { dock.closeAll(g) } })
                return r
            }
            property int menuCurrent: 0
            // The menu's keys: Up/Down move, Return/Enter/Space run, Escape closes.
            function menuKeyPress(key) {
                if (!menuOpen) return false
                if (key === Qt.Key_Escape) menuKey = ""
                else if (key === Qt.Key_Up) menuCurrent = Math.max(0, menuCurrent - 1)
                else if (key === Qt.Key_Down) menuCurrent = Math.min(menuRows.length - 1, menuCurrent + 1)
                else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
                    var r = menuRows[menuCurrent]
                    if (r && r.on) r.run()
                } else return false
                return true
            }

            // The edge window (autohide): 4 px along the whole edge, a 2 px input zone at the screen's edge.
            PanelWindow {
                id: edgeWin
                screen: dock.scr
                visible: dock.autohide
                readonly property bool side: !dock.horiz
                implicitWidth: side ? 4 : 0
                implicitHeight: side ? 0 : 4
                anchors.top: dock.edge !== "bottom"
                anchors.bottom: true
                anchors.left: dock.edge !== "right"
                anchors.right: dock.edge !== "left"
                color: "transparent"
                // At the very edge, over a bar's outer pixels too (Fitts): the edge is the target.
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "kurashi-dock-edge"
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {
                    x: dock.edge === "right" ? edgeWin.width - 2 : 0
                    y: dock.horiz ? edgeWin.height - 2 : 0
                    width: edgeWin.side ? 2 : edgeWin.width
                    height: edgeWin.side ? edgeWin.height : 2
                }
                Item {
                    x: dock.edge === "right" ? parent.width - 2 : 0
                    y: dock.horiz ? parent.height - 2 : 0
                    width: edgeWin.side ? 2 : parent.width
                    height: edgeWin.side ? parent.height : 2
                    HoverHandler { onHoveredChanged: dock.edgeIn = hovered }
                }
            }

            // The dock window: made on the first show and kept (a hidden dock costs the edge window only; K40's
            // shared-window pattern), content-sized, centred on its edge, in the usable area (beside a bar on that edge).
            property bool everShown: false
            onWantShownChanged: if (wantShown) everShown = true
            LazyLoader {
                active: dock.everShown
                PanelWindow {
                    id: win
                    screen: dock.scr
                    visible: dock.wantShown || dock.shownAmt > 0
                    anchors.bottom: dock.edge === "bottom"
                    anchors.left: dock.edge === "left"
                    anchors.right: dock.edge === "right"
                    implicitWidth: dock.winW
                    implicitHeight: dock.winH
                    color: "transparent"
                    exclusionMode: ExclusionMode.Normal
                    exclusiveZone: dock.autohide ? 0 : dock.bodyAcross + dock.edgeGap
                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.namespace: "kurashi-dock"
                    // K59/row 284: this window's tile pair, shared by the body's and the tiles' reliefs (one pair, not
                    // one per Relief), and the pointer light's sensor.
                    property var tileSheet: tilesLoader.item
                    Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
                    LightSense {}
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    // The body's box at rest: a Region on the item would follow the slide's transform only on a resize, and
                    // a dock revealed after it was made hidden kept an input region off the window (measured).
                    mask: Region { x: body.x; y: body.y; width: body.width; height: body.height }
                    // Test only (frontend/test-dock.sh): the window's size and each tile's box in window coordinates, logged once
                    // the dock stands after a change. Off without the variable.
                    readonly property bool geometryLog: Quickshell.env("KURASHI_DOCK_GEOMETRY") === "1"
                    readonly property string geomKey: geometryLog && dock.shownAmt === 1
                        ? dock.keysJson + "/" + dock.icon + "/" + dock.winW + "x" + dock.winH + "/" + dock.edge : ""
                    onGeomKeyChanged: if (geomKey !== "") geomTimer.restart()
                    Timer {
                        id: geomTimer
                        interval: 300
                        onTriggered: {
                            var parts = ["dock-geom", dock.outName, "win", dock.winW, dock.winH]
                            for (var i = 0; i < dock.keys.length; i++) {
                                var it = list.itemAtIndex(i)
                                if (!it || dock.keys[i] === "|") continue
                                var p = it.mapToItem(null, 0, 0)
                                parts.push(dock.keys[i] + "@" + Math.round(p.x) + "," + Math.round(p.y) + "," + dock.icon)
                            }
                            console.log(parts.join(" "))
                        }
                    }


                    Item {
                        id: slider
                        anchors.fill: parent
                        // Slides off its edge by the dock's thickness while hiding.
                        readonly property real away: (1 - dock.shownAmt) * (dock.bodyAcross + dock.edgeGap + dock.room)
                        transform: Translate {
                            x: dock.edge === "left" ? -slider.away : (dock.edge === "right" ? slider.away : 0)
                            y: dock.horiz ? slider.away : 0
                        }
                        opacity: Store.live ? 1 : Theme.staleOpacity

                        Block {
                            id: body
                            x: dock.edge === "left" ? dock.edgeGap : dock.room
                            y: dock.room
                            width: dock.bodyW
                            height: dock.bodyH
                            radius: Theme.rLg + 4
                            fill: Theme.surfaceAlpha
                            flatBorder: Theme.outline
                            animate: win.visible
                            HoverHandler { onHoveredChanged: dock.bodyIn = hovered }
                            WheelHandler {
                                enabled: list.contentWidth > list.width || list.contentHeight > list.height
                                onWheel: function (ev) {
                                    var d = -(ev.angleDelta.y || ev.angleDelta.x) / 2
                                    if (dock.horiz) list.contentX = Math.max(0, Math.min(list.contentWidth - list.width, list.contentX + d))
                                    else list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY + d))
                                }
                            }

                            ListView {
                                id: list
                                x: dock.bodyPad - body.inset
                                y: dock.bodyPad - body.inset
                                width: parent.width - 2 * x
                                height: parent.height - 2 * y
                                orientation: dock.horiz ? ListView.Horizontal : ListView.Vertical
                                spacing: dock.spacing
                                interactive: false
                                clip: contentWidth > width || contentHeight > height
                                model: dock.keys
                                delegate: Item {
                                    id: cell
                                    required property string modelData
                                    readonly property bool isSep: modelData === "|"
                                    readonly property var g: dock.groups.map[modelData]
                                        || (modelData === "+" ? { key: "+", name: I18n.tr("dock.empty.name"), windows: [], pinned: false } : null)
                                    readonly property var wins: g ? g.windows : []
                                    readonly property bool focusedApp: {
                                        for (var i = 0; i < wins.length; i++) if (wins[i].focused) return true
                                        return false
                                    }
                                    readonly property string src: g && g.entry && g.entry.icon ? Quickshell.iconPath(g.entry.icon, true) : ""
                                    width: dock.horiz ? (isSep ? dock.sepW : dock.icon) : dock.cellAcross
                                    height: dock.horiz ? dock.cellAcross : (isSep ? dock.sepW : dock.tileAlong)

                                    Accessible.role: isSep ? Accessible.Separator : Accessible.Button
                                    Accessible.name: g ? g.name : ""
                                    Accessible.description: wins.length > 0
                                        ? I18n.tr("dock.a11y.windows").replace("{n}", wins.length) : ""

                                    // The rule between pinned and running apps.
                                    Rectangle {
                                        visible: cell.isSep
                                        anchors.centerIn: parent
                                        width: dock.horiz ? 1 : dock.icon * 0.6
                                        height: dock.horiz ? dock.icon * 0.6 : 1
                                        color: Theme.outline
                                    }

                                    Block {
                                        id: tile
                                        visible: !cell.isSep
                                        x: dock.edge === "left" ? dock.dotRoom : 0
                                        width: dock.icon
                                        height: dock.icon + Theme.shadowDy
                                        radius: Math.min(Theme.rLg, dock.icon / 2)
                                        ringScale: 0.5
                                        softScale: 0.35
                                        // K61 (docs/ux/texture.md "Controls"): an opaque tile (focused, hovered, its menu open)
                                        // carries the relief over its picture and glyph; a transparent one sits on the dock's
                                        // body and carries none (a halo). In a window that shares its sheet.
                                        relief: !(Theme.texControls && !Theme.texText && fill.a >= 1
                                            && !!(Window.window && QsWindow.window && QsWindow.window.tileSheet))
                                        pressed: tap.pressed
                                        animate: win.visible
                                        fill: cell.focusedApp ? Theme.selected
                                            // The tile whose menu is open stays lit (macOS); the redraw also commits the
                                            // window's keyboard change for the menu (a layer surface's change lands on its
                                            // next commit).
                                            : (hover.hovered || dock.menuKey === cell.modelData ? Theme.containerHigh
                                                : (Theme.groups && Theme.lifted ? Theme.container : "transparent"))
                                        Image {
                                            id: img
                                            anchors.centerIn: parent
                                            width: Math.round(dock.icon * 0.72)
                                            height: width
                                            source: cell.src
                                            sourceSize: Qt.size(96, 96)
                                            asynchronous: true
                                            visible: cell.src !== "" && status === Image.Ready
                                            scale: hover.hovered && Theme.springOn ? 1.15 : 1
                                            Behavior on scale {
                                                enabled: Theme.springOn && win.visible
                                                SpringAnimation { spring: Theme.spring; damping: Theme.damping }
                                            }
                                        }
                                        // No icon (no desktop entry, or the theme lacks it): the app's first letter; the
                                        // empty state's tile shows the launcher symbol.
                                        Icon {
                                            anchors.centerIn: parent
                                            visible: !img.visible && cell.modelData === "+"
                                            name: "apps"
                                            glyph: "+"
                                            size: Math.round(dock.icon * 0.5)
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !img.visible && cell.modelData !== "+"
                                            color: cell.focusedApp ? Theme.fgOnSelected : Theme.fg
                                            font.pixelSize: Math.round(dock.icon * 0.42)
                                            font.weight: Theme.wBold
                                            font.family: Theme.fam(text, Theme.families)
                                            text: cell.g ? String(cell.g.name || "?").charAt(0).toUpperCase() : ""
                                        }
                                        // The relief over the picture and the glyph, when the tile carries it (see `relief`).
                                        Loader {
                                            active: !tile.relief
                                            anchors.fill: parent
                                            sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, Math.min(tile.radius, tile.face.height / 2) - tile.inset) }
                                        }
                                    }
                                    // One dot per window (max four, DMS), toward the screen edge; the focused one wider and
                                    // in the accent, so focus is not colour alone.
                                    Grid {
                                        visible: !cell.isSep && cell.wins.length > 0
                                        rows: dock.horiz ? 1 : Math.min(4, cell.wins.length)
                                        columns: dock.horiz ? Math.min(4, cell.wins.length) : 1
                                        spacing: 3
                                        x: dock.horiz ? (cell.width - width) / 2 : (dock.edge === "left" ? 0 : dock.icon + 2)
                                        y: dock.horiz ? dock.icon + Theme.shadowDy + 2 : (dock.icon - height) / 2
                                        Repeater {
                                            model: Math.min(4, cell.wins.length)
                                            delegate: Rectangle {
                                                required property int index
                                                readonly property bool lit: cell.wins[index] !== undefined && cell.wins[index].focused === true
                                                width: dock.horiz ? (lit ? 10 : 4) : 4
                                                height: dock.horiz ? 4 : (lit ? 10 : 4)
                                                radius: 2
                                                color: lit ? Theme.accent : Theme.dim
                                            }
                                        }
                                    }

                                    HoverHandler {
                                        id: hover
                                        enabled: !cell.isSep
                                        onHoveredChanged: {
                                            if (hovered) { dock.tipTile = tile; dock.tipKey = cell.modelData }
                                            else if (dock.tipKey === cell.modelData) dock.tipKey = ""
                                        }
                                    }
                                    TapHandler {
                                        id: tap
                                        enabled: !cell.isSep
                                        acceptedButtons: Qt.LeftButton
                                        onTapped: dock.activate(cell.g)
                                    }
                                    TapHandler {
                                        enabled: !cell.isSep && cell.g !== null && cell.modelData !== "+"
                                        acceptedButtons: Qt.MiddleButton
                                        onTapped: dock.launch(cell.g)
                                    }
                                    TapHandler {
                                        enabled: !cell.isSep && cell.g !== null && cell.modelData !== "+"
                                        acceptedButtons: Qt.RightButton
                                        onTapped: dock.openMenu(cell.modelData, tile)
                                    }
                                }
                            }
                        }
                    }

                    // The tooltip: the app's name over its tile after a short rest; click-through, made only while shown.
                    Timer {
                        id: tipTimer
                        interval: 400
                        running: dock.tipKey !== "" && !dock.menuOpen
                        onTriggered: tipLoader.active = true
                    }
                    Connections {
                        target: dock
                        function onTipKeyChanged() { if (dock.tipKey === "") tipLoader.active = false }
                        function onMenuKeyChanged() { if (dock.menuKey !== "") tipLoader.active = false }
                    }
                    LazyLoader {
                        id: tipLoader
                        active: false
                        PopupWindow {
                            id: tip
                            readonly property var g: dock.groups.map[dock.tipKey]
                            readonly property string text: dock.noteKey === dock.tipKey && dock.noteText !== "" ? dock.noteText
                                : (dock.tipKey === "+" ? I18n.tr("dock.empty.hint") : (g ? g.name : ""))
                            anchor.item: dock.tipTile
                            anchor.edges: dock.edge === "bottom" ? Edges.Top : (dock.edge === "left" ? Edges.Right : Edges.Left)
                            anchor.gravity: dock.edge === "bottom" ? Edges.Top : (dock.edge === "left" ? Edges.Right : Edges.Left)
                            anchor.margins.top: dock.horiz ? -6 : 0
                            anchor.margins.left: dock.edge === "right" ? -6 : 0
                            anchor.margins.right: dock.edge === "left" ? -6 : 0
                            visible: text !== "" && dock.tipTile !== null
                            implicitWidth: tipBox.width
                            implicitHeight: tipBox.height
                            color: "transparent"
                            mask: Region {}
                            Rectangle {
                                id: tipBox
                                width: tipText.implicitWidth + 2 * Theme.gap
                                height: tipText.implicitHeight + Theme.gap
                                radius: Theme.rSm
                                color: Theme.panel
                                border.width: 1
                                border.color: Theme.outline
                                Text {
                                    id: tipText
                                    anchors.centerIn: parent
                                    text: tip.text
                                    color: Theme.fg
                                    font.pixelSize: Theme.fsCaption
                                    font.family: Theme.fam(text, Theme.families)
                                }
                            }
                        }
                    }

                    // The menu (right click; DMS `DockContextMenuBase.qml`): an overlay over the whole output while it is open,
                    // so a click anywhere outside closes it and the keyboard reaches it (a popup of a layer surface without
                    // keyboard gets none, measured). Made on open, gone on close.
                    LazyLoader {
                        active: dock.menuOpen
                        PanelWindow {
                            id: menu
                            readonly property var g: dock.menuGroup
                            screen: dock.scr
                            anchors { top: true; bottom: true; left: true; right: true }
                            exclusionMode: ExclusionMode.Ignore
                            color: "transparent"
                            WlrLayershell.layer: WlrLayer.Overlay
                            WlrLayershell.namespace: "kurashi-dock-menu"
                            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.AllButtons
                                // A press outside the menu closes it; one on the menu goes to its rows.
                                onPressed: function (ev) {
                                    var inside = ev.x >= menuBody.x && ev.x < menuBody.x + menuBody.width
                                        && ev.y >= menuBody.y && ev.y < menuBody.y + menuBody.height
                                    if (inside) ev.accepted = false
                                    else dock.menuKey = ""
                                }
                            }
                            Item {
                                anchors.fill: parent
                                focus: true
                                Keys.onPressed: function (ev) { ev.accepted = dock.menuKeyPress(ev.key) }
                            }
                            Block {
                                id: menuBody
                                readonly property rect at: dock.menuAt
                                x: dock.horiz ? Math.max(Theme.gap, Math.min(menu.width - width - Theme.gap, at.x + at.width / 2 - width / 2))
                                    : (dock.edge === "left" ? at.x + at.width + Theme.gap : at.x - Theme.gap - width)
                                y: dock.horiz ? at.y - Theme.gap - height
                                    : Math.max(Theme.gap, Math.min(menu.height - height - Theme.gap, at.y + at.height / 2 - height / 2))
                                width: Math.max(180, col.implicitWidth + 2 * Theme.gap + 2 * inset)
                                height: col.implicitHeight + 2 * Theme.gap + 2 * inset + Theme.shadowDy
                                radius: Theme.rLg
                                fill: Theme.panel
                                flatBorder: Theme.outline
                                softScale: 0.6
                                Column {
                                    id: col
                                    x: Theme.gap
                                    y: Theme.gap
                                    width: menuBody.width - 2 * Theme.gap - 2 * menuBody.inset
                                    Text {
                                        width: parent.width
                                        leftPadding: Theme.gap
                                        bottomPadding: Theme.xs
                                        text: menu.g ? menu.g.name : ""
                                        elide: Text.ElideRight
                                        color: Theme.dim
                                        font.pixelSize: Theme.fsCaption
                                        font.weight: Theme.wBold
                                        font.family: Theme.fam(text, Theme.families)
                                    }
                                    Repeater {
                                        model: dock.menuRows
                                        delegate: Rectangle {
                                            id: row
                                            required property var modelData
                                            required property int index
                                            width: col.width
                                            height: Theme.controlH
                                            radius: Theme.rSm
                                            color: (rowHover.hovered || dock.menuCurrent === index) && modelData.on ? Theme.containerHigh : "transparent"
                                            opacity: modelData.on ? 1 : 0.5
                                            Accessible.role: Accessible.MenuItem
                                            Accessible.name: modelData.text
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: Theme.gap
                                                text: row.modelData.text
                                                color: Theme.fg
                                                font.pixelSize: Theme.fs
                                                font.family: Theme.fam(text, Theme.families)
                                            }
                                            HoverHandler { id: rowHover; onHoveredChanged: if (hovered) dock.menuCurrent = row.index }
                                            TapHandler { enabled: row.modelData.on; onTapped: row.modelData.run() }
                                        }
                                    }
                                    // Why Pin is inert, or why the write did not take (Shōjiki).
                                    Text {
                                        visible: text !== ""
                                        width: parent.width
                                        leftPadding: Theme.gap
                                        topPadding: Theme.xs
                                        wrapMode: Text.Wrap
                                        text: dock.menuError !== "" ? dock.menuError
                                            : (dock.pinForcedBy !== "" ? I18n.tr("dock.menu.forced").replace("{by}", dock.pinForcedBy) : "")
                                        color: dock.menuError !== "" ? Theme.error : Theme.dim
                                        font.pixelSize: Theme.fsCaption
                                        font.family: Theme.fam(text, Theme.families)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
