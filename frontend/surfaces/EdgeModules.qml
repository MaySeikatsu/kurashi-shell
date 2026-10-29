import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/sidebar"
import "../components/bar/framegeom.js" as FG
import "../components/modules" as M

// The edge modules of one output (K71, K72; docs/ux/edge-modules.md — Caelestia's drawers): on every edge without a bar,
// each non-empty zone (`runtime.layout` `edges.<e>.zones.<start|center|end>`) is one group pinned to the edge at the zone's
// place (start / centre / end; a side edge's run top → bottom), its modules side by side through ModuleHost, grown out of
// what is under it — the frame's band, or the screen edge without a frame — by the edge's draw (the mode table's "island /
// edge module" row): dynamic, the island's neck — concave fillets of `join_radius` into the band (ColumnShape, as the
// dock); connected, the same with straight joins; floating, a pill `gap` off the band (the look's Block).
//
// Visibility per edge (K71): `always` — the group's glances stay out; `hover` — nothing at rest but the edge's shared strip
// (EdgeStrips) and no loaded module; the pointer resting `layout.reveal_delay` on the zone's third of the edge grows that
// group only, and it folds back 400 ms after the pointer left it and the strip — never while one of its peeks, menus or
// cards is open or it holds the keyboard; `empty_desktop` — out while the output's workspace has no window, else as hover;
// `hidden` — out while `runtime.ui.shown` lists `module:<edge>:<zone>@<output>` (`layout.toggle`), with the keyboard
// (OnDemand): Tab walks its modules, Enter opens one's expanded view, Esc or a click elsewhere puts it away. The standalone
// island (user point 11: `island` in a bar-less zone) grows its collapsed group out while a transient face (volume,
// brightness, power, Bluetooth) is up, when `island.main.system_events` is on, and folds back with it.
//
// Motion: the group grows across from the band on the island's spring (K65), its fillets with it; reduced motion cuts.
// Ma: the window exists only while the group is out or growing, or while it keeps the edge's zone; its modules are loaded
// only while it shows. Zones (the one-holder rule, K71): the window keeps the edge's exclusive zone only when the layout
// names `module` the holder, and then only the first non-empty zone's group (start, centre, end) — exactly one window.
// The window spans its whole edge (input only on the group): an origin a module registers for the Stage (AnchorReport)
// is then in the output's px on a top or bottom edge, as a bar's.
Scope {
    id: em
    required property var modelData
    signal trayMenuRequested(string id)

    Watch { doc: "runtime.layout" }
    Watch { doc: "runtime.ui" }

    component Group: Scope {
        id: g
        required property string edge
        required property string zone

        readonly property var scr: em.modelData
        readonly property string outName: scr ? scr.name : ""
        readonly property bool vertical: edge === "left" || edge === "right"
        readonly property int thick: Theme.barH

        // ---- the layout (PROTOCOL §3.1), through strings so a document patch remakes nothing that did not change --------
        readonly property bool hasDoc: ShellLayout.doc.outputs !== undefined
        readonly property var lay: ShellLayout.of(outName)
        readonly property var ed: ShellLayout.edgeOf(outName, edge)
        readonly property string entriesKey: hasDoc && ed.bar !== true ? JSON.stringify(((ed.zones || {})[zone]) || []) : "[]"
        readonly property var entries: JSON.parse(entriesKey)
        readonly property bool on: entries.length > 0
        readonly property string visibility: ed.visibility || "always"
        readonly property string draw: ed.draw || "dynamic"
        readonly property bool floating: draw === "floating"
        readonly property int inset: Math.max(0, Math.round(ed.inset || 0))
        readonly property bool frameOn: (lay.frame || {}).on === true
        readonly property int frameRadius: frameOn ? Math.max(0, Math.round((lay.frame || {}).radius || 0)) : 0
        // The line the group grows from: the band's inner edge (the screen edge without a frame); a floating pill stands
        // `gap` off it, so it comes out from behind the same line.
        readonly property int baseLine: floating ? Math.max(0, inset - ShellLayout.gap) : inset
        readonly property string firstZone: {
            var z = ed.zones || {}, order = ["start", "center", "end"]
            for (var i = 0; i < order.length; i++) if ((z[order[i]] || []).length > 0) return order[i]
            return ""
        }
        readonly property bool holdsZone: on && ed.holder === "module" && firstZone === zone
        readonly property int reserve: Math.max(0, Math.round(ed.reserve || 0))
        readonly property bool keepsSpace: holdsZone && reserve > 0
        // Dynamic ↔ connected morphs the fillets (the radius moves over `motion.std`), never a jump.
        // (K74: on a framed output the hole's one radius, `frame.radius`; the layout's `join_radius` without a frame)
        readonly property int joinR: draw === "dynamic" ? (frameOn ? frameRadius : ShellLayout.joinRadius) : 0
        property real aR: joinR
        Behavior on aR { enabled: Theme.springOn && g.shownAmt > 0; NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutCubic } }

        // ---- where it stands along the edge ----
        readonly property real edgeLen: scr ? (vertical ? scr.height : scr.width) : 0
        // What stands across this edge's ends (K71: the horizontal bars own the corners, the side bars run between them):
        // a bar there that is not hidden (its inset and thickness), else the band beside; past it the frame's inner corner.
        function clearOf(e) {
            var x = ShellLayout.edgeOf(outName, e)
            var c = x.bar === true && x.visibility !== "hidden" ? Math.round(x.inset || 0) + thick : FG.band(lay, e)
            return c + frameRadius + ShellLayout.gap
        }
        readonly property real startClear: clearOf(vertical ? "top" : "left")
        readonly property real endClear: clearOf(vertical ? "bottom" : "right")
        // The modules' run (px along the edge), latched while the group folds back with its modules unloaded.
        property real runLen: 0
        readonly property real padAlong: Theme.pad + (floating ? Theme.xs : 0)
        readonly property real bodyLen: Math.round(Math.max(thick, runLen + 2 * padAlong))
        // Where the body starts along the edge (output px from the edge's left or top end): the fillets need `joinR` beside.
        readonly property real bodyStart: Math.round(zone === "start" ? startClear + joinR
            : zone === "end" ? edgeLen - endClear - joinR - bodyLen : (edgeLen - bodyLen) / 2)
        // The zone's span on the edge's strip: its third (the dwell there reveals this group only).
        readonly property real spanFrom: zone === "start" ? 0 : zone === "center" ? edgeLen / 3 : 2 * edgeLen / 3
        readonly property real spanTo: zone === "start" ? edgeLen / 3 : zone === "center" ? 2 * edgeLen / 3 : edgeLen

        // ---- visibility ----
        readonly property var uiDoc: Store.docs["runtime.ui"] || ({})
        readonly property string target: "module:" + edge + ":" + zone
        readonly property bool forced: {
            var s = uiDoc.shown
            return on && Array.isArray(s) && (s.indexOf(target + "@" + outName) >= 0 || s.indexOf(target + "@*") >= 0)
        }
        Watch { doc: "svc.workspaces"; active: g.on && g.visibility === "empty_desktop" }
        readonly property bool emptyDesk: {
            var t = (Store.docs["svc.workspaces"] || {}).tasks
            if (!t) return false
            var l = t[outName] || t["*"]
            return Array.isArray(l) && l.length === 0
        }
        // The standalone island's transient faces (user point 11): watched only while the group could be folded.
        readonly property bool hasIsland: entries.some(function (e) { return e.id === "island" })
        Watch { doc: "config"; active: g.on && g.hasIsland }
        readonly property bool systemEvents: {
            var c = Store.docs["config"] || {}, k = "island.main.system_events"
            var o = c.outputs && c.outputs[outName] ? c.outputs[outName][k] : undefined
            var p = o !== undefined ? o : (c.values ? c.values[k] : undefined)
            return !p || p.value !== false
        }
        Watch { doc: "runtime.island.main"; active: g.on && g.hasIsland && g.systemEvents && g.visibility !== "always" }
        readonly property bool transientUp: hasIsland && systemEvents
            && ["volume", "brightness", "power", "bluetooth"].indexOf((Store.docs["runtime.island.main"] || {}).face) >= 0

        readonly property bool hoverOn: on && !forced && (visibility === "hover" || (visibility === "empty_desktop" && !emptyDesk))
        EdgeReveal {
            id: reveal
            screen: g.scr
            edge: g.edge
            key: "module:" + g.zone
            enabled: g.hoverOn
            from: g.spanFrom
            to: g.spanTo
            // (A pointer resting on the edge keeps it out by itself: EdgeReveal keeps its strip while revealed, row 524.)
            holdIn: g.holdOpen || g.edgeLatch
        }
        // What keeps a revealed group out: the pointer on it, one of its menus or drags, a card or a peek on this output, its
        // keyboard focus.
        property bool pointerOn: false
        // The pointer that brought it out, between the strip's leave and the window's enter (the Bar's rule): held from the
        // reveal until the window has seen the pointer come or go, or 1.2 s.
        property bool edgeLatch: false
        Connections {
            target: reveal
            function onRevealedChanged() { g.edgeLatch = reveal.revealed; if (reveal.revealed) latchT.restart() }
        }
        onPointerOnChanged: edgeLatch = false
        property Timer latchT: Timer { interval: 1200; onTriggered: g.edgeLatch = false }
        property bool focused: false
        readonly property M.ModuleLink link: M.ModuleLink { vertical: g.vertical }
        readonly property bool holdOpen: pointerOn || focused || link.busy || !!uiDoc.panel
            || (!!uiDoc.peek && (uiDoc.peek.output === undefined || uiDoc.peek.output === outName))
        readonly property bool wantShown: on && (visibility === "always" || forced
            || (visibility === "empty_desktop" && emptyDesk) || reveal.revealed || transientUp)
        // Something to show: a group whose modules are all absent now (a recorder that records nothing) grows nothing.
        readonly property bool hasContent: winL.item !== null && winL.item.runNow > 0
        // 0 = folded into its line, 1 = out; the island's spring between (K65), cut when motion is off.
        // (K74: Caelestia's curves while the motion is timed, a spring while it springs; Glide)
        readonly property real shownAmt: glide.value
        readonly property Glide glide: Glide { to: g.wantShown && g.hasContent ? 1 : 0; damping: Math.max(Theme.damping, 0.5); epsilon: 0.005 }
        readonly property real grow: Math.max(0, Math.min(1.12, shownAmt))
        readonly property bool windowWanted: on && (wantShown || shownAmt > 0 || keepsSpace)
        function putAway() { if (forced) Store.act("layout.toggle", { target: g.target, output: g.outName }) }
        // A card opened from the keyboard-revealed group is up (see the body's focus): the group goes once it closes.
        property bool afterCard: false
        readonly property bool cardUp: !!uiDoc.panel
        onCardUpChanged: if (!cardUp && afterCard) { afterCard = false; putAway() }
        onForcedChanged: if (!forced) afterCard = false

        // Test only (KURASHI_EDGE_GEOMETRY=1, frontend/test-edge-modules.sh): `EDGEGROUP <output> <edge> <zone> <vis> <draw>
        // out|in body x y w h` (output px) and one `EDGEMOD <output> <edge> <zone> <id> x0 y0 x1 y1` per present module, a
        // moment after the group settles; `EDGEGROUP … none` once it has no window. Without the variable: no timer, no log.
        readonly property bool geoLog: Quickshell.env("KURASHI_EDGE_GEOMETRY") === "1"
        property Timer geoT: Timer { interval: 500; onTriggered: g.logGeo() }
        function requestGeo() { if (geoLog && on) geoT.restart() }
        onShownAmtChanged: if (shownAmt === 0 || shownAmt === 1) requestGeo()
        onEntriesKeyChanged: requestGeo()
        onDrawChanged: requestGeo()
        onInsetChanged: requestGeo()
        onWindowWantedChanged: requestGeo()
        Connections {
            target: reveal
            enabled: g.geoLog
            function onRevealedChanged() {
                console.log("EDGEREVEAL " + g.outName + " " + g.edge + " " + g.zone + " " + reveal.revealed + " t=" + Date.now()
                    + " p=" + Math.round(reveal.p) + " hold=" + reveal.onSpan + " holdOpen=" + g.holdOpen)
            }
        }
        function logGeo() {
            var head = "EDGEGROUP " + outName + " " + edge + " " + zone + " " + visibility + " " + draw + " "
            var w = winL.item
            if (!w) { console.log(head + "none"); return }
            var o = w.sheetOrigin, b = w.bodyBox()
            console.log(head + (shownAmt > 0.5 ? "out" : "in") + " body "
                + [o.x + b.x, o.y + b.y, b.w, b.h].map(Math.round).join(" ") + " holder " + (holdsZone ? reserve : 0))
            var hs = w.hosts()
            for (var i = 0; i < hs.length; i++) {
                var h = hs[i]
                if (!h.present || !h.visible) continue
                var p = h.mapToItem(null, 0, 0)
                console.log("EDGEMOD " + outName + " " + edge + " " + zone + " " + h.mid + " "
                    + [o.x + p.x, o.y + p.y, o.x + p.x + h.width, o.y + p.y + h.height].map(Math.round).join(" "))
            }
        }

        LazyLoader {
            id: winL
            active: g.windowWanted
            PanelWindow {
                id: win
                screen: g.scr
                anchors {
                    top: g.edge !== "bottom"
                    bottom: g.edge !== "top"
                    left: g.edge !== "right"
                    right: g.edge !== "left"
                }
                // Across: the edge's inset, the group, and room for the spring's overshoot and the floating pill's shadow.
                readonly property int shadowRoom: g.floating && Theme.lifted
                    ? Math.ceil(Math.max(Math.abs(Theme.sinkX), Math.abs(Theme.sinkY), Theme.shadowDy) + Theme.softR) : 0
                readonly property int across: g.inset + g.thick + Math.max(6, shadowRoom)
                implicitHeight: g.vertical ? 0 : across
                implicitWidth: g.vertical ? across : 0
                color: "transparent"
                exclusionMode: g.holdsZone ? ExclusionMode.Normal : ExclusionMode.Ignore
                // (Quickshell turns the mode to Normal whenever `exclusiveZone` is written: only while it holds.)
                Binding on exclusiveZone { when: g.holdsZone; value: Math.max(g.reserve, SidebarGeom.openZone(g.outName, g.edge)); restoreMode: Binding.RestoreNone }
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "kurashi-edge-module"
                WlrLayershell.keyboardFocus: g.forced && g.visibility === "hidden" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                visible: g.wantShown || g.shownAmt > 0 || g.keepsSpace

                // A side holder is placed inside the zones of the holders mapped before it (shell.qml maps the bars first).
                readonly property int zoneBefore: g.vertical && g.holdsZone ? Light.zoneOf(win, "top") : 0
                readonly property point sheetOrigin: {
                    var s = g.scr
                    if (!s) return Qt.point(0, 0)
                    if (g.vertical) return Qt.point(g.edge === "left" ? 0 : s.width - width, zoneBefore)
                    return Qt.point(0, g.edge === "top" ? 0 : s.height - height)
                }
                readonly property string zoneKey: [g.outName, g.edge, backingWindowVisible && g.holdsZone ? g.reserve : 0].join("|")
                onZoneKeyChanged: Light.setZone(win, g.outName, g.edge, backingWindowVisible && g.holdsZone ? g.reserve : 0)
                Component.onDestruction: { Light.setZone(win, "", g.edge, 0); SidebarGeom.clear(g.outName, "group:" + g.zone, g.edge) }
                // I258 (row 556): a joined group on a framed edge whose band is ruled (line chrome) covers the band's rule
                // with its body and fillets: the rule opens there (SidebarGeom, as a column's and the dock's), so the
                // group's outline runs round its fillets into the rule's ends — one sheet, no line under the group.
                readonly property string openingKey: !g.floating && g.frameOn && shape.ruled && g.grow > 0
                    ? [Math.round(g.bodyStart - g.aR), Math.round(g.bodyStart + g.bodyLen + g.aR)].join(",") : ""
                onOpeningKeyChanged: {
                    SidebarGeom.clear(g.outName, "group:" + g.zone, g.edge)
                    if (openingKey === "") return
                    var v = openingKey.split(",")
                    SidebarGeom.set(g.outName, "group:" + g.zone, g.edge, Number(v[0]), Number(v[1]))
                }

                // K59: this window's tile pair for the reliefs, and the pointer light's sensor.
                property var tileSheet: tilesLoader.item
                Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
                LightSense {}

                // ---- the body in window coordinates: along from the window's start, across from the edge ----
                readonly property real bodyAlong: g.bodyStart - (g.vertical ? zoneBefore : 0)
                // The body's far side from the edge at rest (the band line + the group), and as drawn now.
                readonly property real farRest: g.baseLine + g.thick + (g.floating ? ShellLayout.gap : 0)
                readonly property real nearRest: g.floating ? g.inset : g.baseLine
                readonly property real farNow: g.baseLine + (farRest - g.baseLine) * g.grow
                // The body's box at rest (input, the geometry log): x, y, w, h in the window.
                function boxAt(near, far) {
                    var len = g.bodyLen, t = far - near
                    if (g.edge === "top") return { x: bodyAlong, y: near, w: len, h: t }
                    if (g.edge === "bottom") return { x: bodyAlong, y: height - far, w: len, h: t }
                    if (g.edge === "left") return { x: near, y: bodyAlong, w: t, h: len }
                    return { x: width - far, y: bodyAlong, w: t, h: len }
                }
                function bodyBox() { return boxAt(nearRest, farRest) }
                readonly property var restBox: boxAt(nearRest, farRest)
                // Input: the group at rest and the band under it to the screen's edge (Caelestia's hit zone: the module's span
                // on the band), while it is out or coming out. Mapped under the resting pointer that brought it out, the
                // window takes it from the strip at once but is told so only ~0.5 s later (sway, measured: leave, then the
                // enter): `edgeLatch` holds the group across that gap.
                readonly property var hitBox: boxAt(0, farRest)
                // (Never an empty region: a 0×0 mask reads as none, the whole window takes input — and the resting pointer
                // with it, measured. A zone holder folded at rest keeps one pixel at its far corner, inside its own zone.)
                readonly property bool inputOn: g.wantShown || g.shownAmt > 0
                mask: Region {
                    x: win.inputOn ? win.hitBox.x : (g.edge === "right" ? 0 : win.width - 1)
                    y: win.inputOn ? win.hitBox.y : (g.edge === "bottom" ? 0 : win.height - 1)
                    width: win.inputOn ? win.hitBox.w : 1
                    height: win.inputOn ? win.hitBox.h : 1
                }
                // Glass only (Theme.blur): behind the group's body as drawn — the floating pill round, the joined body (its
                // frame mirrored back to the window) at its free corners (I276).
                BackgroundEffect.blurRegion: Region {
                    id: blurAll
                    readonly property bool on: Theme.blur && g.grow > 0
                    item: on && g.floating ? pill : null
                    radius: Math.min(pill.width, pill.height) / 2
                    Region {
                        readonly property rect b: shape.bodyRect
                        x: g.edge === "left" ? win.width - b.x - b.width : b.x
                        y: g.edge === "bottom" ? win.height - b.y - b.height : b.y
                        width: blurAll.on && !g.floating ? b.width : 0
                        height: blurAll.on && !g.floating ? b.height : 0
                        topLeftRadius: shape.sTL
                        topRightRadius: shape.sTR
                        bottomLeftRadius: shape.sBL
                        bottomRightRadius: shape.sBR
                    }
                }
                Item {
                    x: win.hitBox.x
                    y: win.hitBox.y
                    width: win.hitBox.w
                    height: win.hitBox.h
                    HoverHandler {
                        onHoveredChanged: {
                            g.pointerOn = hovered
                            if (g.geoLog) console.log("EDGEHOVER " + g.outName + " " + g.edge + " " + g.zone + " " + hovered + " t=" + Date.now())
                        }
                    }
                }

                // ---- the shape ----
                // Joined (dynamic, connected): nothing is drawn on the edge's side of the band line (the band is
                // translucent: an overlap would show), so the group comes out of it.
                Item {
                    id: clipper
                    readonly property int cut: g.baseLine
                    x: g.edge === "left" ? cut : 0
                    y: g.edge === "top" ? cut : 0
                    width: parent.width - (g.vertical ? cut : 0)
                    height: parent.height - (g.vertical ? 0 : cut)
                    clip: true
                    Item {
                        id: frameIt
                        x: -clipper.x
                        y: -clipper.y
                        width: win.width
                        height: win.height
                        opacity: Store.live ? 1 : Theme.staleOpacity

                        // ColumnShape's canonical frame (the dock's): a top group's edge is the frame's top, a bottom one's
                        // the top mirrored down; a side group's edge is its outer (right) side, a left one mirrored.
                        Item {
                            visible: !g.floating && g.grow > 0
                            width: win.width
                            height: win.height
                            transform: Scale {
                                xScale: g.edge === "left" ? -1 : 1
                                yScale: g.edge === "bottom" ? -1 : 1
                                origin.x: win.width / 2
                                origin.y: win.height / 2
                            }
                            ColumnShape {
                                id: shape
                                anchors.fill: parent
                                x0: g.vertical ? win.width - win.farNow : win.bodyAlong
                                x1: g.vertical ? win.width - g.baseLine : win.bodyAlong + g.bodyLen
                                y0: g.vertical ? win.bodyAlong : g.baseLine
                                y1: g.vertical ? win.bodyAlong + g.bodyLen : win.farNow
                                openT: !g.vertical
                                openO: g.vertical
                                neckT: g.aR
                                neckO: g.aR
                                // K74: its free corners are corners of the hole, as its fillets (0 = connected, straight)
                                radius: Math.min(g.joinR, g.thick / 2)
                                squareOuter: false
                                flipY: g.edge === "bottom"
                                flipX: g.edge === "left"
                                ruled: Theme.frameOutline
                                fill: Theme.surfaceAlpha
                            }
                        }
                        // Floating: the look's own pill, a gap off the band, sliding out from behind it.
                        Block {
                            id: pill
                            visible: g.floating && g.grow > 0
                            readonly property real away: (1 - g.grow) * (win.farRest - g.baseLine + win.shadowRoom + 2)
                            x: win.restBox.x + (g.edge === "left" ? -away : g.edge === "right" ? away : 0)
                            y: win.restBox.y + (g.edge === "top" ? -away : g.edge === "bottom" ? away : 0)
                            width: win.restBox.w
                            height: win.restBox.h + Theme.shadowDy
                            radius: Theme.rFull
                            fill: Theme.surfaceAlpha
                            animate: false
                        }

                        // ---- the modules, on the body: loaded only while the group shows (Ma) ----
                        FocusScope {
                            id: body
                            readonly property real away: g.floating ? pill.away : (win.farRest - win.farNow)
                            x: win.restBox.x + (g.edge === "left" ? -away : g.edge === "right" ? away : 0)
                            y: win.restBox.y + (g.edge === "top" ? -away : g.edge === "bottom" ? away : 0)
                            width: win.restBox.w
                            height: win.restBox.h
                            visible: g.shownAmt > 0 || content.active
                            focus: g.forced
                            Keys.onEscapePressed: g.putAway()
                            // Brought out by key it holds the keyboard: losing it (a click elsewhere) puts it away — but a
                            // card it opened (Enter on a module) takes the keyboard too: then it stays out under the card and
                            // goes when the card closes, its errand done.
                            property bool hadFocus: false
                            onActiveFocusChanged: {
                                g.focused = activeFocus
                                if (activeFocus) { hadFocus = true; g.afterCard = false }
                                else if (hadFocus) {
                                    hadFocus = false
                                    if (g.uiDoc.panel) g.afterCard = true
                                    else g.putAway()
                                }
                            }
                            Accessible.role: Accessible.Grouping
                            Accessible.name: I18n.tr("edge-modules.group.a11y")
                                .replace("{edge}", I18n.tr("edge-modules.edge." + g.edge))
                                .replace("{zone}", I18n.tr("edge-modules.zone." + g.zone))
                                .replace("{modules}", g.entries.map(function (e) {
                                    return e.kind === "mod" ? (e.mod || e.id) : I18n.tr("layout.module." + e.id)
                                }).join(", "))
                            Accessible.description: I18n.tr("edge-modules.group.hint")

                            Loader {
                                id: content
                                active: g.wantShown || g.shownAmt > 0
                                anchors.centerIn: parent
                                sourceComponent: g.vertical ? columnRun : rowRun
                                onLoaded: if (g.forced) Qt.callLater(win.focusFirst)
                            }
                        }
                    }
                }
                readonly property real runNow: content.item ? (g.vertical ? content.item.height : content.item.width) : 0
                onRunNowChanged: if (runNow > 0 && Math.abs(runNow - g.runLen) > 0.5) g.runLen = runNow
                function hosts() {
                    var r = content.item ? content.item.rep : null, out = []
                    if (r) for (var i = 0; i < r.count; i++) if (r.itemAt(i)) out.push(r.itemAt(i))
                    return out
                }
                // Revealed by key: the keyboard goes to its first module.
                function focusFirst() {
                    var hs = hosts()
                    for (var i = 0; i < hs.length; i++) {
                        var h = hs[i]
                        if (!h.present || !h.visible) continue
                        var f = h.activeFocusOnTab ? h : h.nextItemInFocusChain(true)
                        if (f) { f.forceActiveFocus(Qt.TabFocusReason); return }
                    }
                    body.forceActiveFocus()
                }
                Connections {
                    target: g
                    function onForcedChanged() { if (g.forced && content.item) Qt.callLater(win.focusFirst) }
                }

                Component {
                    id: rowRun
                    Row {
                        readonly property alias rep: rowRep
                        spacing: Theme.pad
                        Repeater { id: rowRep; model: g.entries; delegate: hostOf }
                    }
                }
                Component {
                    id: columnRun
                    Column {
                        readonly property alias rep: colRep
                        spacing: Theme.pad
                        Repeater { id: colRep; model: g.entries; delegate: hostOf }
                    }
                }
                Component {
                    id: hostOf
                    M.ModuleHost {
                        required property var modelData
                        entry: modelData
                        vertical: g.vertical
                        thickness: g.thick
                        edge: g.edge
                        output: g.outName
                        screen: g.scr
                        live: g.shownAmt > 0 || g.wantShown
                        anchored: true
                        link: g.link
                        keys: true
                        anchors.verticalCenter: g.vertical ? undefined : (parent ? parent.verticalCenter : undefined)
                        anchors.horizontalCenter: g.vertical ? (parent ? parent.horizontalCenter : undefined) : undefined
                        onTrayMenuRequested: id => em.trayMenuRequested(id)
                        onBusyChanged: g.link.hold("host:" + mid, busy)
                        Component.onDestruction: g.link.hold("host:" + mid, false)
                    }
                }
            }
        }
    }

    Group { edge: "top"; zone: "start" }
    Group { edge: "top"; zone: "center" }
    Group { edge: "top"; zone: "end" }
    Group { edge: "bottom"; zone: "start" }
    Group { edge: "bottom"; zone: "center" }
    Group { edge: "bottom"; zone: "end" }
    Group { edge: "left"; zone: "start" }
    Group { edge: "left"; zone: "center" }
    Group { edge: "left"; zone: "end" }
    Group { edge: "right"; zone: "start" }
    Group { edge: "right"; zone: "center" }
    Group { edge: "right"; zone: "end" }
}
