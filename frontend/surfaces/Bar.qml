import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../core/mods.js" as Mods
import "../components"
import "../components/island"
import "../components/sidebar"
import "../components/bar"
import "../components/bar/framegeom.js" as FG
import "../components/modules" as M
import "../components/decor" as Decor

// The bar on one edge of one output (K71, docs/ux/layout.md): there while `runtime.layout` has `edges.<edge>.bar` for this
// output, its rows (top, bottom) or columns (left, right) the edge's zones `start`, `center`, `end`, each entry a module
// (K72, components/modules: ModuleHost). Everything shown comes from Store; every click becomes an act or an intent.
//
// Draw (K71): docked (dynamic, connected) — flush on its edge, the frame's band there; floating — a rounded pill `inset`
// (band + gap) from its edge and `band + gap` from the bands beside it, in every chrome (the look's Block: its outline,
// ring and shadow), the groups standing on it. A docked bar on a framed output carries its edge's frame strip (row 492 b):
// its window reaches past the bar by the fillets, which hang under its ends, and it keeps the frame's zone there.
//
// Visibility (K71): `always`; `hover` — out after the pointer rests on its edge (EdgeReveal: the edge's one shared strip,
// the dwell, twice as long on an edge another output touches), back 400 ms after it left the bar and the edge, never while one of its
// menus, peeks or cards is open; `empty_desktop` — out while the output's workspace has no window, else as hover; `hidden`
// — out only while `runtime.ui.shown` lists `bar:<edge>@<output>` (`layout.toggle`), closed by the same, Esc or a click
// elsewhere. It slides in from its edge on the motion springs (K65; cut with reduced motion). While hidden it has no
// window — unless it keeps a zone (`reserve` on) or carries the frame's strip — and its modules hold no subscription (Ma).
//
// Zones (the one-holder rule, K71): the window keeps its edge's exclusive zone only when the layout names the bar the
// holder (`holder: "bar"`, also on a framed edge whose strip it carries: row 510); otherwise it ignores zones and stands
// at its inset.
// Mapping order matters (W43-frame probe: a holder is placed inside the zones of holders mapped before it): shell.qml
// maps the top and bottom bars first and the side bars after them (`after`), so a side bar runs between them.
Scope {
    id: bar
    required property var modelData
    property string edge: "top"
    // shell.qml: the bars (and frame strips) this one is placed after are on screen, or none is wanted.
    property bool after: true
    signal trayMenuRequested(string id)

    readonly property var scr: modelData
    readonly property string outName: scr ? scr.name : ""
    readonly property bool vertical: edge === "left" || edge === "right"

    // Where the bar stands (PROTOCOL §3.1): held while the shell runs, it decides whether the bar exists at all.
    Watch { doc: "runtime.layout" }
    readonly property var lay: ShellLayout.of(outName)
    readonly property var ed: ShellLayout.edgeOf(outName, edge)
    // Plain values (they notify only when they change): every document patch re-reads the layout, and rebuilt lists would
    // remake items — a frame drawn for nothing (Ma).
    readonly property bool on: ed.bar === true
    readonly property string visibility: ed.visibility || "always"
    readonly property bool drawFloating: ed.draw === "floating"
    readonly property int inset: Math.max(0, Math.round(ed.inset || 0))
    readonly property int reserve: Math.max(0, Math.round(ed.reserve || 0))
    readonly property bool frameOn: (lay.frame || {}).on === true
    readonly property int frameRadius: Math.max(0, Math.round((lay.frame || {}).radius || 0))
    readonly property int bandTop: FG.band(lay, "top")
    readonly property int bandBottom: FG.band(lay, "bottom")
    readonly property int bandLeft: FG.band(lay, "left")
    readonly property int bandRight: FG.band(lay, "right")
    function bandBeside(e) { return e === "top" ? bandTop : e === "bottom" ? bandBottom : e === "left" ? bandLeft : bandRight }
    // Row 492 (b): a docked bar on a framed output is its edge's strip.
    readonly property bool carries: on && FG.docked(lay, edge)
    // The openings of the columns and the dock on the bands this bar's strip carries (SidebarGeom; through a string).
    readonly property string frameOpeningsKey: carries && Theme.frameOutline
        ? JSON.stringify(SidebarGeom.openingsOf(outName).filter(function (o) { return o.edge !== edge })) : "[]"
    readonly property var frameOpenings: JSON.parse(frameOpeningsKey)
    // The one-holder rule (K71): the layout names the bar (row 510: also on a framed edge whose strip it carries).
    readonly property bool holdsZone: on && ed.holder === "bar"
    readonly property int barH: Theme.barH

    // Where the bar starts and ends along its edge, from the screen's start and end on it. A side bar runs between the
    // horizontal bars (they own the corners): its `span` (row 511, the daemon's; + gap when it floats). A floating top or
    // bottom bar stands `band + gap` in from the bands beside it.
    readonly property var span: ed.span || ({})
    readonly property int startOff: vertical ? Math.max(0, Math.round(span.start || 0))
        : (drawFloating ? bandLeft + ShellLayout.gap : 0)
    readonly property int endOff: vertical ? Math.max(0, Math.round(span.end || 0))
        : (drawFloating ? bandRight + ShellLayout.gap : 0)

    // ---- the zones: module entries (`{id, kind, mod?, provide?}`), through a string so they change only with their content
    // Before any layout document: the schema's default zones, `mods` standing for every enabled mod widget.
    readonly property bool noDoc: ShellLayout.doc.outputs === undefined
    Watch { doc: "mods"; active: bar.noDoc && bar.on }
    readonly property string zonesKey: {
        if (!noDoc) return JSON.stringify(ed.zones || { start: [], center: [], end: [] })
        var core = function (id) { return { id: id, kind: "core" } }
        var mods = Mods.widgets(Store.docs["mods"]).map(function (w) {
            return { id: "mod:" + w.mod + ":" + String(w.provide).substring(7), kind: "mod", mod: w.mod, provide: w.provide }
        })
        return JSON.stringify({
            start: edge === "top" ? ["sidebar_left", "workspaces", "windows"].map(core) : [],
            center: edge === "top" ? [core("island")] : [],
            end: edge === "top" ? [core("volume")].concat(mods, ["recorder", "keyboard", "clock", "quick", "tray", "sidebar_right"].map(core)) : []
        })
    }
    readonly property var zones: JSON.parse(zonesKey)
    // The modules whose neighbours stand close (the workspace keys and the sidebar buttons beside them); the others are
    // `Theme.pad` apart.
    readonly property var tightIds: ["workspaces", "sidebar_left", "sidebar_right"]
    // A zone as runs, each run one group block (chromes with groups): the island stands alone (its pill is its block), the
    // window list is a group of its own, every other stretch one group; a run's pieces are one module each, or a stretch of
    // tight ones. `key`: the group's origin key (Stage reads these three).
    function runsOf(zone, list) {
        var runs = [], cur = null, rightUsed = false
        function close() { if (cur) runs.push(cur); cur = null }
        for (var i = 0; i < list.length; i++) {
            var e = list[i]
            if (e.id === "island" || e.id === "windows") {
                close()
                runs.push({ kind: e.id, key: e.id === "windows" ? "group:tasks" : "", pieces: [[e]] })
                continue
            }
            if (!cur) cur = { kind: "group", key: "", pieces: [] }
            var tight = tightIds.indexOf(e.id) >= 0
            var last = cur.pieces.length > 0 ? cur.pieces[cur.pieces.length - 1] : null
            if (tight && last && last.tight) last.push(e)
            else { var p = [e]; p.tight = tight; cur.pieces.push(p) }
        }
        close()
        for (var j = 0; j < runs.length; j++) {
            var r = runs[j]
            if (r.kind !== "group") continue
            var ids = [].concat.apply([], r.pieces).map(function (x) { return x.id })
            if (ids.indexOf("workspaces") >= 0) r.key = "group:workspaces"
            else if (zone === "end" && !rightUsed) { r.key = "group:right"; rightUsed = true }
            else r.key = "group:" + zone + ":" + j
            // (A piece's `tight` mark does not survive JSON: keep it as data.)
            r.pieces = r.pieces.map(function (p) { return { tight: !!p.tight, entries: p.slice() } })
        }
        for (var k = 0; k < runs.length; k++)
            if (runs[k].kind !== "group") runs[k].pieces = [{ tight: false, entries: runs[k].pieces[0] }]
        return runs
    }

    // ---- visibility ---------------------------------------------------------------------------------------------------
    readonly property var uiDoc: Store.docs["runtime.ui"] || ({})
    readonly property bool forced: {
        var s = uiDoc.shown
        if (!Array.isArray(s)) return false
        return s.indexOf("bar:" + edge + "@" + outName) >= 0 || s.indexOf("bar:" + edge + "@*") >= 0
    }
    // The desk is empty: this output's active workspace holds no window (svc.workspaces `tasks`, as the dock reads it).
    Watch { doc: "svc.workspaces"; active: bar.on && bar.visibility === "empty_desktop" }
    readonly property bool emptyDesk: {
        var t = (Store.docs["svc.workspaces"] || {}).tasks
        if (!t) return false
        var l = t[outName] || t["*"]
        return Array.isArray(l) && l.length === 0
    }
    EdgeReveal {
        id: reveal
        screen: bar.scr
        edge: bar.edge
        key: "bar"
        enabled: bar.on && !bar.forced && (bar.visibility === "hover" || (bar.visibility === "empty_desktop" && !bar.emptyDesk))
        holdIn: bar.holdOpen
    }
    // What keeps a revealed bar out: the pointer on it, one of its menus or drags, a card or a peek on this output, its focus;
    // the pointer resting on the edge is EdgeReveal's (the strip stays under the bar, row 524).
    property bool pointerOn: false
    property bool focused: false
    readonly property bool holdOpen: pointerOn || focused || link.busy || !!uiDoc.panel
        || (!!uiDoc.peek && (uiDoc.peek.output === undefined || uiDoc.peek.output === outName))
    readonly property bool wantShown: on && (visibility === "always" || forced
        || (visibility === "empty_desktop" && emptyDesk) || reveal.revealed)
    // 0 = slid out past its edge, 1 = in place: on Caelestia's curves (expressive: the bar grows out of the band and
    // overshoots a little) or a spring (calm, lively; K65), cut when motion is off (K74, Glide).
    readonly property real shownAmt: glide.value
    readonly property Glide glide: Glide { to: bar.wantShown ? 1 : 0; damping: Math.max(Theme.damping, 0.6) }
    // The window: while the bar is out or sliding, while it keeps a zone or carries the frame's strip (both hold while it
    // is in), and — once shown — kept unmapped while hidden (the dock's pattern; BENCH "W44 bar": the cheaper of the two).
    readonly property bool keepsSpace: holdsZone && reserve > 0
    property bool everShown: false
    onWantShownChanged: if (wantShown) everShown = true
    // (Bench only: KURASHI_BAR_DROP=1 makes no window while hidden, the other choice measured.)
    readonly property bool keepWindow: Quickshell.env("KURASHI_BAR_DROP") !== "1"
    readonly property bool windowWanted: on && (wantShown || shownAmt > 0 || keepsSpace || carries || (everShown && keepWindow))
    readonly property bool mapped: winL.item !== null && winL.item.backingWindowVisible === true
    // shell.qml: what waits for this bar (the side bars, the frame's side strips) may go once it is on screen or not wanted.
    readonly property bool settled: !(on && (wantShown || keepsSpace || carries)) || mapped

    // The one bar of this output the Stage and the peeks take as "the bar" (BarConfig.edge: the island's, else the first).
    BarConfig { id: cfg; screen: bar.scr }
    readonly property bool primary: cfg.enabled && cfg.edge === edge
    onPrimaryChanged: if (primary) Peeks.setEdge(outName, edge)
    Component.onCompleted: { if (primary) Peeks.setEdge(outName, edge); report() }

    // Where the body stands from its edge, for the neck, the sidebar's join and the frame (IslandGeom's bar registry).
    // Also the window's content item and its place on the output, so the Stage can tell which bar an origin stands in and
    // where (row 512: a floating bar's window does not start at the output's corner).
    readonly property point winOrigin: winL.item ? winL.item.sheetOrigin : Qt.point(0, 0)
    readonly property string geomKey: [outName, edge, on, inset, barH, drawFloating, mapped, winOrigin.x, winOrigin.y,
                                       scr ? scr.width : 0].join("|")
    function report() {
        IslandGeom.setBar(outName, edge, on ? { inset: inset, size: barH, floating: drawFloating, mapped: mapped,
                                               root: winL.item ? winL.item.contentItem : null, ox: winOrigin.x, oy: winOrigin.y,
                                               sw: scr ? scr.width : 0 } : null)
    }
    onGeomKeyChanged: report()
    Component.onDestruction: IslandGeom.setBar(outName, edge, null)

    readonly property M.ModuleLink link: M.ModuleLink { vertical: bar.vertical }

    LazyLoader {
        id: winL
        active: bar.windowWanted && bar.after
        PanelWindow {
            id: win
            screen: bar.scr
            // QuickButton and SidebarButton read it (their origins register on top and bottom bars only).
            readonly property bool vertical: bar.vertical

            // K59: this window's tile pair, shared by its reliefs (components/TileSheet.qml), and the pointer light's sensor.
            property var tileSheet: tilesLoader.item
            Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
            LightSense {}

            // ---- geometry: the body (the bar itself) inside the window ----
            // A floating bar's window reaches from its edge (margin 0, as a zone holder must: its margin would add to its
            // zone) and round the body by the look's shadow; a carrying bar's reaches past the bar by the frame's fillets.
            readonly property int shadowRoom: bar.drawFloating && Theme.lifted
                ? Math.ceil(Math.max(Math.abs(Theme.sinkX), Math.abs(Theme.sinkY), Theme.shadowDy) + Theme.softR) : 0
            readonly property int edgeRoom: bar.drawFloating ? bar.inset : 0
            readonly property int awayRoom: shadowRoom
            readonly property int startRoom: Math.min(shadowRoom, bar.startOff)
            readonly property int endRoom: Math.min(shadowRoom, bar.endOff)
            readonly property var g: bar.carries ? FG.geometry(bar.lay, bar.barH, bar.scr ? bar.scr.width : 0, bar.scr ? bar.scr.height : 0,
                                                               Theme.frameOutlineW, FG.zones(bar.lay), Theme.squircle) : null
            readonly property string piecesKey: bar.carries && g !== null && (bar.edge === "top" || bar.edge === "bottom")
                ? JSON.stringify(FG.across(g, bar.edge === "top")) : ""
            readonly property var pieces: piecesKey !== "" ? JSON.parse(piecesKey) : null
            readonly property int carryDepth: pieces ? Math.max(0, Math.ceil(pieces.d) - bar.barH) : 0
            // A carrying bar that slides (hover, empty desktop): the frame's band stays on its edge — the bar is the band
            // grown thick (Caelestia's border and bar, docs/ux/frame.md). `bodyDepth`: how far the body's inner edge stands
            // from the screen edge now; the cut (where the fillets hang) never nearer the edge than the frame's thickness.
            readonly property real bodyDepth: !bar.carries ? bar.barH
                : body.over + (bar.edge === "top" ? body.y + bar.barH
                : bar.edge === "bottom" ? (bar.scr ? bar.scr.height : 0) - sheetOrigin.y - body.y
                : bar.edge === "left" ? body.x + bar.barH
                : (bar.scr ? bar.scr.width : 0) - sheetOrigin.x - body.x)
            readonly property int frameT: Math.max(0, Math.round((bar.lay.frame || {}).thickness || 0))
            readonly property real cutDepth: Math.max(frameT, bodyDepth)
            // The band shows below (above) the body while the body is slid out past the frame's thickness.
            readonly property bool bandShows: bar.carries && bodyDepth < frameT - 0.5
            // How much nearer its edge this bar's cut stands than at rest: the fillets the frame's strips (or another bar's)
            // hang on this edge follow it (IslandGeom.lifts).
            // (negative while the bar overshoots past its rest: the fillets hang further in)
            readonly property real ownLift: bar.carries ? bar.barH - cutDepth : 0
            onOwnLiftChanged: IslandGeom.setLift(bar.outName, bar.edge, ownLift, win)
            Component.onCompleted: IslandGeom.setLift(bar.outName, bar.edge, ownLift, win)
            function liftOn(e) { return e === bar.edge ? ownLift : IslandGeom.liftOf(bar.outName, e) }
            // Where the cut stands on edge `e` now, from the screen's edge: its band, a docked bar's thickness, less its lift.
            function cutOf(e) { return bar.bandBeside(e) + (FG.docked(bar.lay, e) ? bar.barH : 0) - liftOn(e) }
            readonly property int thick: edgeRoom + bar.barH + awayRoom + carryDepth
            // The side bar's start and end on the output: a holder is placed inside the zones of the holders mapped before it
            // (the top and bottom bars or the frame's strips; shell.qml's order), so its margins count from there.
            readonly property int zoneBeforeTop: bar.vertical && bar.holdsZone ? Light.zoneOf(win, "top") : 0
            readonly property int zoneBeforeBottom: bar.vertical && bar.holdsZone ? Light.zoneOf(win, "bottom") : 0

            anchors {
                top: bar.edge === "top" || bar.vertical
                bottom: bar.edge === "bottom" || bar.vertical
                left: bar.edge === "left" || !bar.vertical
                right: bar.edge === "right" || !bar.vertical
            }
            implicitHeight: bar.vertical ? 0 : thick
            implicitWidth: bar.vertical ? thick : 0
            margins {
                top: bar.edge === "top" ? (bar.drawFloating ? 0 : bar.inset)
                    : (bar.vertical ? Math.max(0, bar.startOff - win.startRoom - win.zoneBeforeTop) : 0)
                bottom: bar.edge === "bottom" ? (bar.drawFloating ? 0 : bar.inset)
                    : (bar.vertical ? Math.max(0, bar.endOff - win.endRoom - win.zoneBeforeBottom) : 0)
                left: bar.edge === "left" ? (bar.drawFloating ? 0 : bar.inset) : (!bar.vertical ? bar.startOff - win.startRoom : 0)
                right: bar.edge === "right" ? (bar.drawFloating ? 0 : bar.inset) : (!bar.vertical ? bar.endOff - win.endRoom : 0)
            }
            readonly property int edgeMargin: bar.drawFloating ? 0 : bar.inset
            color: "transparent"
            // The zone (the compositor adds the margin on its edge): the edge's whole reserve, never less than the bar it is.
            readonly property int zoneTotal: !bar.holdsZone ? 0
                : (bar.visibility === "always" ? Math.max(bar.reserve, bar.inset + bar.barH) : bar.reserve)
            // (Quickshell switches to Normal whenever `exclusiveZone` is written, so it is written only while the bar holds the
            // zone; a window that holds none stays Ignore, -1 on the wire.)
            exclusionMode: bar.holdsZone ? ExclusionMode.Normal : ExclusionMode.Ignore
            // (with the zone a sidebar that keeps space only while it is out takes then: I301)
            // (an int property: it changes only with the number — every layout patch re-reads the layout, and a zone written
            // again, even unchanged, is a commit: an idle bar must not commit, test-frame)
            readonly property int sideOpenZone: SidebarGeom.openZone(bar.outName, bar.edge)
            Binding on exclusiveZone { when: bar.holdsZone; value: Math.max(0, Math.max(win.zoneTotal, win.sideOpenZone) - win.edgeMargin); restoreMode: Binding.RestoreNone }
            WlrLayershell.layer: WlrLayer.Top
            // A hidden bar brought out by key takes the keyboard on demand, like the sidebar (Esc puts it away).
            WlrLayershell.keyboardFocus: bar.forced && bar.visibility === "hidden" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            visible: bar.wantShown || bar.shownAmt > 0 || bar.keepsSpace || bar.carries
            // The body's box at rest while it is out or coming out (the dock's rule): an input region that slid in with the
            // body would only be found by the next motion. Revealed on hover, the 2 px on the screen's edge stay the shared
            // strip's, which keeps the bar out while the pointer rests there (EdgeReveal, row 524).
            readonly property int edgeCut: reveal.cutFor(bar.inset)
            // The rule as drawn (the test log's; none under a chrome without a rule or a floating bar).
            readonly property var ruleSegs: !bar.drawFloating && Theme.frameOutline ? bg.ruleSegs : []
            mask: Region {
                x: body.restX + (bar.edge === "left" ? win.edgeCut : 0)
                y: body.restY + (bar.edge === "top" ? win.edgeCut : 0)
                width: body.shownNow ? Math.max(0, body.width - (bar.vertical ? win.edgeCut : 0)) : 0
                height: body.shownNow ? Math.max(0, body.height - (bar.vertical ? 0 : win.edgeCut)) : 0
            }

            // Its exclusive zone, for the origins of windows the compositor places beside it (Light.originOf); registered once
            // it is on screen (the frame's side strips wait for it).
            readonly property var zoneKey: [bar.outName, bar.edge, backingWindowVisible ? zoneTotal : 0].join("|")
            onZoneKeyChanged: Light.setZone(win, bar.outName, bar.edge, backingWindowVisible ? zoneTotal : 0)
            Component.onDestruction: { Light.setZone(win, "", bar.edge, 0); IslandGeom.dropLift(bar.outName, bar.edge, win) }
            // Row 490: where this window really stands on its output (the sheet's registration; Light.originOf reads it).
            readonly property point sheetOrigin: {
                var s = bar.scr
                if (!s) return Qt.point(0, 0)
                var x = margins.left, y = margins.top
                if (bar.edge === "right") x = s.width - width - margins.right
                if (bar.edge === "bottom") y = s.height - height - margins.bottom
                if (bar.vertical) y = zoneBeforeTop + margins.top
                return Qt.point(x, y)
            }
            // K61 carried sheet: the body's distance from its place at rest while it slides.
            readonly property point sheetCarry: Qt.point(body.x - body.restX, body.y - body.restY)

            // ext-background-effect-v1 blur (no-op where the compositor lacks the protocol): the body, and the frame's fills
            // this window carries.
            // Glass only (Theme.blur). The body as drawn: a floating bar's pill round, a docked strip square; nothing for a
            // clear strip (its groups are pills of their own) — a square region showed the blur past the outline (I276).
            BackgroundEffect.blurRegion: Region {
                item: Theme.blur && body.shownNow && !bb.clearStrip ? bg : null
                radius: bar.drawFloating ? Math.min(bg.width, bg.height) / 2 : 0
                Region { item: Theme.blur && carried.item ? carried.item.fillAt(0) : null }
                Region { item: Theme.blur && carried.item && carried.item.fillCount > 1 ? carried.item.fillAt(1) : null }
                Region { item: Theme.blur && carried.item && carried.item.fillCount > 2 ? carried.item.fillAt(2) : null }
            }

            // Row 492 (b): the frame's strip on this edge (its side bands to the fillets' end, the fillets, the rule's arcs).
            Loader {
                id: carried
                // (a side bar carries no pieces — the frame's top and bottom strips hang its fillets — only its band's cover)
                active: bar.carries
                // The sheet under the body; the rule over it (`carriedRule`, after the body, I302).
                readonly property bool rule: false
                sourceComponent: carriedPieces
            }
            Component {
                id: carriedPieces
                FramePieces {
                    drawSheet: !parent.rule
                    drawRule: parent.rule
                    ox: win.sheetOrigin.x
                    oy: win.sheetOrigin.y
                    winW: win.width
                    winH: win.height
                    sw: bar.scr ? bar.scr.width : 0
                    sh: bar.scr ? bar.scr.height : 0
                    r: bar.frameRadius
                    ow: Theme.frameOutlineW
                    cr: ShellLayout.screenRadius
                    seed: bar.edge === "top" ? 0xF2A1 : 0xF2A2
                    fills: win.pieces ? win.pieces.fills : []
                    fillets: win.pieces ? win.pieces.fillets : []
                    rules: win.pieces ? win.pieces.rules : []
                    arcs: win.pieces ? win.pieces.arcs : []
                    // (the openings of a column or the dock that meets this strip's side bands, as the frame's own strips)
                    openings: bar.frameOpenings
                    coverOpenings: win.bandShows && ow > 0
                        ? SidebarGeom.openingsOf(bar.outName).filter(function (o) { return o.edge === bar.edge }) : []
                    liftTop: win.liftOn("top")
                    liftBottom: win.liftOn("bottom")
                    liftLeft: win.liftOn("left")
                    liftRight: win.liftOn("right")
                    readonly property real sw0: bar.scr ? bar.scr.width : 0
                    readonly property real sh0: bar.scr ? bar.scr.height : 0
                    readonly property real near: Math.max(0, win.bodyDepth)
                    readonly property real t: win.frameT
                    // The band where the body is not (along the whole window; a side bar's runs between the strips).
                    cover: !win.bandShows ? { x: 0, y: 0, w: 0, h: 0 }
                        : bar.edge === "top" ? { x: 0, y: near, w: sw0, h: t - near }
                        : bar.edge === "bottom" ? { x: 0, y: sh0 - t, w: sw0, h: t - near }
                        : bar.edge === "left" ? { x: near, y: win.sheetOrigin.y, w: t - near, h: win.height }
                        : { x: sw0 - t, y: win.sheetOrigin.y, w: t - near, h: win.height }
                    // Its rule along the band's inner edge, between the fillets of the strips beside it.
                    readonly property real ra: bar.vertical ? win.sheetOrigin.y + bar.frameRadius : win.cutOf("left") + bar.frameRadius
                    readonly property real rb: bar.vertical ? win.sheetOrigin.y + win.height - bar.frameRadius
                        : sw0 - win.cutOf("right") - bar.frameRadius
                    coverRule: !(win.bandShows && ow > 0) ? { x: 0, y: 0, w: 0, h: 0 }
                        : bar.edge === "top" ? { x: ra, y: t - ow, w: rb - ra, h: ow }
                        : bar.edge === "bottom" ? { x: ra, y: sh0 - t, w: rb - ra, h: ow }
                        : bar.edge === "left" ? { x: t - ow, y: ra, w: ow, h: rb - ra, vert: true }
                        : { x: sw0 - t, y: ra, w: ow, h: rb - ra, vert: true }
                }
            }

            Item {
                id: body
                // At rest: past the edge room, the start room and (bottom, right) the carried depth.
                readonly property real restX: bar.edge === "right" ? win.width - win.edgeRoom - bar.barH
                    : (bar.edge === "left" ? win.edgeRoom : win.startRoom)
                readonly property real restY: bar.edge === "bottom" ? win.height - win.edgeRoom - bar.barH
                    : (bar.edge === "top" ? win.edgeRoom : win.startRoom)
                // Slid out: past its edge, with its shadow.
                readonly property real away: Math.max(0, 1 - bar.shownAmt) * (bar.barH + win.edgeRoom + win.awayRoom + 2)
                // Past rest on an overshooting curve (K74, expressive): the bar's inner edge reaches further in and settles
                // back — Caelestia's bar widening past its content — while the body stays on its edge (a docked bar only:
                // a floating pill has no edge to grow from). The strip's fill and rule follow its inner edge.
                readonly property real over: bar.drawFloating ? 0 : Math.max(0, bar.shownAmt - 1) * bar.barH
                readonly property bool shownNow: bar.shownAmt > 0
                x: restX + (bar.edge === "left" ? -away : bar.edge === "right" ? away : 0)
                y: restY + (bar.edge === "top" ? -away : bar.edge === "bottom" ? away : 0)
                width: bar.vertical ? bar.barH : win.width - win.startRoom - win.endRoom
                height: bar.vertical ? win.height - win.startRoom - win.endRoom : bar.barH
                visible: shownNow
                focus: bar.forced
                Keys.onEscapePressed: bar.putAway()
                // Brought out by key, it had the keyboard: a click elsewhere takes it, and puts the bar away.
                onActiveFocusChanged: {
                    bar.focused = activeFocus
                    if (!activeFocus && hadFocus) { hadFocus = false; bar.putAway() }
                    else if (activeFocus) hadFocus = true
                }
                property bool hadFocus: false
                HoverHandler { onHoveredChanged: bar.pointerOn = hovered }

                Item {
                    id: bb
                    anchors.fill: parent
                    // The chrome decides how the bar's groups stand (K42, K45), from tokens only (rule 4):
                    // - flat (`chrome.groups` false): one solid strip, the rows on it;
                    // - groups with a shadow of either kind (keycap, soft): the groups float as blocks on the desk, the strip is clear;
                    // - groups without a shadow (line): a terminal's status line — the strip, its inner edge ruled in the outline, and
                    //   each group an outlined box with no fill behind its text.
                    // Side bars keep their strip: their items are not grouped. A floating bar is a pill in every chrome, the groups on it;
                    // a docked bar on a framed output is the band, so its strip is drawn even where the groups float.
                    readonly property bool floatingGroups: Theme.groups && Theme.lifted && !bar.vertical
                    readonly property bool clearStrip: floatingGroups && !bar.drawFloating && !bar.frameOn
                    readonly property bool live: bar.shownAmt > 0

                    Rectangle {
                        id: bg
                        anchors.fill: parent
                        anchors.bottomMargin: bar.edge === "top" ? -body.over : 0
                        anchors.topMargin: bar.edge === "bottom" ? -body.over : 0
                        anchors.rightMargin: bar.edge === "left" ? -body.over : 0
                        anchors.leftMargin: bar.edge === "right" ? -body.over : 0
                        color: bb.clearStrip || bar.drawFloating || ground.has ? "transparent" : Theme.surfaceAlpha
                        // W53.2: the look's bar ground (`[slots] bar`: XP's glossy taskbar, 7's glass superbar) in place of the
                        // strip's fill; nothing is made without one.
                        Decor.BarGround {
                            id: ground
                            anchors.fill: parent
                            active: has && !bar.drawFloating
                            edge: bar.edge
                        }
                        // The strip's inner edge, ruled in the outline (line chrome; 0 px under flat). While the island's shape is out on
                        // this bar (W30, IslandGeom.openL/R) the rule is left out under the shape's box, which draws the rule there
                        // itself, in step with the card: round the hanging card's fillets into its sides, never under a translucent
                        // card. The opening stands still while the card morphs, so the two surfaces never disagree mid-morph.
                        readonly property bool opened: !bar.vertical && bar.primary && IslandGeom.openR > IslandGeom.openL
                            && IslandGeom.takenOn !== "" && IslandGeom.takenOn === bar.outName
                        // Row 363 (W34): an open sidebar at rest on this edge leaves the rule out over the span its column covers
                        // (SidebarGeom, along the output's edge: from the bar's own start here), so the column's outline runs round its
                        // fillet into the rule's end — one sheet, no seam. Every column that meets this bar opens it (row 521: both
                        // sidebars out at once; a column joining a top and a bottom bar opens both).
                        readonly property var sideOpen: SidebarGeom.openingsIn(bar.outName, bar.edge, bar.vertical ? win.sheetOrigin.y : win.sheetOrigin.x)
                        // The rule as segments along the edge: everything but the island's opening and the sidebars' spans.
                        readonly property real ruleLen: bar.vertical ? height : width
                        readonly property var ruleSegs: {
                            var gaps = []
                            if (opened) gaps.push([Math.max(0, width / 2 + IslandGeom.openL), width / 2 + IslandGeom.openR])
                            for (var s = 0; s < sideOpen.length; s++)
                                gaps.push([Math.max(0, sideOpen[s].from), Math.min(ruleLen, sideOpen[s].to)])
                            // K71: on a framed output the bar's rule ends where the frame's fillet begins; the frame's rule turns
                            // round it into the band beside (FramePieces).
                            // (Where the fillets end, from this window's own start and end: a side bar's window starts at the band
                            // or past a docked bar, and a sliding bar beside it brings its fillet nearer the screen's edge.)
                            if (bar.frameOn && !bar.drawFloating) {
                                var fr = bar.frameRadius, e0 = bar.vertical ? "top" : "left", e1 = bar.vertical ? "bottom" : "right"
                                var o0 = bar.vertical ? win.sheetOrigin.y : win.sheetOrigin.x
                                var len = bar.scr ? (bar.vertical ? bar.scr.height : bar.scr.width) : 0
                                var o1 = len - o0 - ruleLen
                                var cut0 = win.cutOf(e0), cut1 = win.cutOf(e1)
                                gaps.push([0, Math.max(0, cut0 + fr - o0)])
                                gaps.push([ruleLen - Math.max(0, cut1 + fr - o1), ruleLen])
                            }
                            // I305 (user: a gap): groups floating with a shadow (keycap, soft) break the rule under them, their
                            // shadow's sideways reach and a few px beside, so the rule and the shadows never run together.
                            if (bb.floatingGroups && bar.zoneRoot && bar.zoneRoot.groupSpans) {
                                var reach = Math.abs(Theme.sinkX) + 3, gs = bar.zoneRoot.groupSpans
                                for (var g = 0; g < gs.length; g++)
                                    gaps.push([Math.max(0, gs[g][0] - reach), Math.min(ruleLen, gs[g][1] + reach)])
                            }
                            gaps.sort(function (x, y) { return x[0] - y[0] })
                            var segs = [], at = 0
                            for (var i = 0; i < gaps.length; i++) {
                                if (gaps[i][0] > at) segs.push([at, gaps[i][0]])
                                at = Math.max(at, gaps[i][1])
                            }
                            if (at < ruleLen) segs.push([at, ruleLen])
                            return segs
                        }
                        // Floating (K71, image 8): the look's own Block — fill, outline, ring, shadow and pen — with rounded ends.
                        Loader {
                            active: bar.drawFloating
                            sourceComponent: Block {
                                width: bg.width
                                height: bg.height + Theme.shadowDy
                                radius: Theme.rFull
                                fill: Theme.surfaceAlpha
                                animate: false
                            }
                        }
                        // K59: the strip's material, under its rules (a floating pill's Block carries its own).
                        Loader {
                            anchors.fill: parent
                            active: !bb.clearStrip && !bar.drawFloating && Theme.texShell
                            sourceComponent: Relief { anchors.fill: parent }
                        }
                        // K62: with a pen in effect the rule is drawn by the pen, as one open line (two, either side of the island's
                        // opening); the opening and the line's ends are the rectangles' below.
                        Loader {
                            id: rulePen
                            anchors.fill: parent
                            visible: !win.bandShows
                            active: Theme.penOutline && !bar.drawFloating && Theme.frameOutline
                            sourceComponent: PenOutline {
                                readonly property real ow: Theme.frameOutlineW
                                readonly property real cy: bar.edge === "top" ? height - ow / 2 : ow / 2
                                readonly property real cx: bar.edge === "left" ? width - ow / 2 : ow / 2
                                color: Theme.frameOutlineColor
                                lineWidth: ow
                                seed: bar.vertical ? 0xB4A2 : 0xB4A1
                                radius: 0
                                paths: bg.ruleSegs.map(function (g) {
                                    return bar.vertical ? { points: [{ x: cx, y: g[0] }, { x: cx, y: g[1] }], closed: false }
                                                        : { points: [{ x: g[0], y: cy }, { x: g[1], y: cy }], closed: false }
                                })
                            }
                        }
                        Repeater {
                            model: !bar.drawFloating && Theme.frameOutline && !rulePen.active ? bg.ruleSegs : []
                            Rectangle {
                                required property var modelData
                                // (inside the frame's band while the body is slid out past it: the band's rule stands there)
                                visible: !win.bandShows
                                // (the frame outline's, I303: on for keycap and line chrome, the bar's inner side as the frame's)
                                color: Theme.frameOutlineColor
                                x: bar.vertical ? (bar.edge === "left" ? bg.width - width : 0) : modelData[0]
                                y: bar.vertical ? modelData[0] : (bar.edge === "top" ? bg.height - height : 0)
                                width: bar.vertical ? Theme.frameOutlineW : Math.max(0, modelData[1] - modelData[0])
                                height: bar.vertical ? Math.max(0, modelData[1] - modelData[0]) : Theme.frameOutlineW
                            }
                        }
                        // Row 596: under the bevel chrome the strip's screen-facing side is a window's raised edge — on a
                        // bottom (or right) bar the light pair, `bevelLight2` outside then `bevelLight` (98's taskbar top,
                        // measured); on a top (or left) bar the dark pair, `bevelDark` outside then `bevelDark2`.
                        Loader {
                            anchors.fill: parent
                            active: Theme.bevelW > 0 && !bar.drawFloating && !bb.clearStrip
                            sourceComponent: Item {
                                readonly property real w: Theme.crisp(1, Screen.devicePixelRatio)
                                readonly property bool lit: bar.edge === "bottom" || bar.edge === "right"
                                Repeater {
                                    model: 2
                                    Rectangle {
                                        required property int index
                                        readonly property real at: index * parent.w
                                        color: parent.lit ? (index === 0 ? Theme.bevelLight2 : Theme.bevelLight)
                                                          : (index === 0 ? Theme.bevelDark : Theme.bevelDark2)
                                        x: !bar.vertical ? 0 : (bar.edge === "right" ? at : parent.width - at - parent.w)
                                        y: bar.vertical ? 0 : (bar.edge === "bottom" ? at : parent.height - at - parent.w)
                                        width: bar.vertical ? parent.w : parent.width
                                        height: bar.vertical ? parent.height : parent.w
                                    }
                                }
                            }
                        }
                    }

                    // One layout is active at a time: a row on top and bottom bars, a column on left and right. Nothing is made while
                    // the bar is out of sight, so its modules hold no subscriptions (Ma).
                    Loader {
                        anchors.fill: parent
                        active: bb.live && !bar.vertical
                        sourceComponent: horizontalLayout
                    }
                    Loader {
                        anchors.fill: parent
                        active: bb.live && bar.vertical
                        sourceComponent: verticalLayout
                    }
                }
            }
            // The frame's rule this window carries, over the body: the arcs meet the body's outline (I302).
            Loader {
                id: carriedRule
                active: bar.carries
                readonly property bool rule: true
                sourceComponent: carriedPieces
            }
        }
    }
    function putAway() { if (forced) Store.act("layout.toggle", {target: "bar:" + edge, output: outName}) }

    // How far a group's row sits in from the bar's end (the group's padding); 0 under flat chrome.
    readonly property real groupInset: Theme.groups ? Theme.gap + 2 + Theme.xs : 0
    readonly property real tightSpacing: vertical ? Theme.gap : (Theme.groups ? Theme.xs + 1 : Theme.gap)
    readonly property bool stale: !Store.live

    // Test only (KURASHI_BAR_GEOMETRY=1, frontend/test-bars.sh): which module stands where — one line per present module,
    // `BARZONE <output> <edge> <zone> <id> x0 y0 x1 y1` in output px, and the window, `BARWIN <output> <edge> x y w h` —
    // logged a moment after a change. Without the variable: no timer, no log.
    readonly property bool zoneLog: Quickshell.env("KURASHI_BAR_GEOMETRY") === "1"
    property var zoneRoot: null
    function hostsIn(item, out) {
        if (!item) return out
        if (item.mid !== undefined && item.slotHeights !== undefined && item.geo !== undefined) { out.push(item); return out }
        var ch = item.children
        for (var i = 0; i < ch.length; i++) hostsIn(ch[i], out)
        return out
    }
    function logZones() {
        var w = winL.item
        if (!w || !zoneRoot) return
        var o = w.sheetOrigin, out = ["BARWIN " + outName + " " + edge + " " + [o.x, o.y, w.width, w.height].map(Math.round).join(" ")
            + " " + (w.visible ? "shown" : "hidden")]
        var hosts = hostsIn(zoneRoot, [])
        for (var i = 0; i < hosts.length; i++) {
            var h = hosts[i]
            if (!h.present || !h.visible) continue
            var p = h.mapToItem(null, 0, 0)
            var zone = zones.start.some(function (e) { return e.id === h.mid }) ? "start"
                : zones.center.some(function (e) { return e.id === h.mid }) ? "center" : "end"
            out.push("BARZONE " + outName + " " + edge + " " + zone + " " + h.mid + " "
                + [o.x + p.x, o.y + p.y, o.x + p.x + h.width, o.y + p.y + h.height].map(Math.round).join(" "))
        }
        // The rule's segments along the edge (line chrome; "-" while it draws none), in px from the bar's own start.
        out.push("BARRULE " + outName + " " + edge + " " + (w.ruleSegs.length > 0
            ? w.ruleSegs.map(function (g) { return Math.round(g[0]) + "-" + Math.round(g[1]) }).join(",") : "-"))
        for (var k = 0; k < out.length; k++) console.log(out[k])
    }
    property Timer zoneT: Timer { interval: 600; onTriggered: bar.logZones() }
    function requestZones() { if (zoneLog) zoneT.restart() }
    onZonesKeyChanged: requestZones()
    onShownAmtChanged: if (shownAmt === 1 || shownAmt === 0) requestZones()
    property Connections zoneDocs: Connections {
        target: Store
        enabled: bar.zoneLog
        function onDocsChanged() { bar.requestZones() }
    }
    property Connections zoneOpenings: Connections {
        target: SidebarGeom
        enabled: bar.zoneLog
        function onOpeningsChanged() { bar.requestZones() }
    }

    // ---- top and bottom bars: the zones as rows — start from the left, center in the middle, end at the right -----------
    Component {
        id: horizontalLayout
        Item {
            id: hl
            anchors.fill: parent
            // The group blocks along the bar (I305: the strip's rule breaks under them).
            readonly property var groupSpans: startRow.groupSpans.concat(centerRow.groupSpans, endRow.groupSpans)
            Component.onCompleted: { bar.zoneRoot = hl; bar.requestZones() }
            opacity: bar.stale ? Theme.staleOpacity : 1
            Behavior on opacity {
                enabled: bar.shownAmt > 0
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }
            ZoneRow {
                id: startRow
                owner: bar
                zone: "start"
                runs: bar.runsOf("start", bar.zones.start || [])
                height: hl.height
                limit: centerRow.width > 0 ? centerRow.x : endRow.x
                anchors { left: parent.left; leftMargin: Theme.pad + bar.groupInset }
            }
            // Disconnected glyph: instantiated only while stale (nothing at idle), after the start zone.
            Loader {
                anchors { left: startRow.right; leftMargin: Theme.gap; verticalCenter: parent.verticalCenter }
                active: bar.stale && bar.primary
                sourceComponent: Text {
                    color: Theme.accent
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: "⊘ " + I18n.tr("frontend.bar.disconnected")
                }
            }
            ZoneRow {
                id: centerRow
                owner: bar
                zone: "center"
                runs: bar.runsOf("center", bar.zones.center || [])
                height: hl.height
                anchors.horizontalCenter: parent.horizontalCenter
            }
            ZoneRow {
                id: endRow
                owner: bar
                zone: "end"
                runs: bar.runsOf("end", bar.zones.end || [])
                height: hl.height
                anchors { right: parent.right; rightMargin: Theme.pad + bar.groupInset }
            }
        }
    }

    // ---- left and right bars: the zones as columns — start from the top, center in the middle, end at the bottom ---------
    // Each module takes the bar's width: text is not turned, the values are shortened and their full text is the accessible
    // name (I85). The end column holds the leading slots that fit between the center and the bar's end; the rest hide from
    // the end, with the count "+N". A sidebar button that ends the end zone stands at the very end (I154).
    // A zone's pieces: a stretch of tight modules is one piece, the others one each.
    function piecesOf(list) {
        var out = []
        for (var i = 0; i < list.length; i++) {
            var tight = tightIds.indexOf(list[i].id) >= 0
            var last = out.length > 0 ? out[out.length - 1] : null
            if (tight && last && last.tight) last.entries.push(list[i])
            else out.push({ tight: tight, entries: [list[i]] })
        }
        return out
    }
    Component {
        id: verticalLayout
        Item {
            id: vl
            anchors.fill: parent
            opacity: bar.stale ? Theme.staleOpacity : 1
            Behavior on opacity {
                enabled: bar.shownAmt > 0
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }
            readonly property var endAll: bar.zones.end || []
            readonly property bool endButton: endAll.length > 0
                && (endAll[endAll.length - 1].id === "sidebar_right" || endAll[endAll.length - 1].id === "sidebar_left")
            readonly property var endList: endButton ? endAll.slice(0, endAll.length - 1) : endAll

            ZoneColumn {
                id: startCol
                owner: bar
                pieces: bar.piecesOf(bar.zones.start || [])
                roomEnd: centerCol.height > 0 ? centerCol.y : endCol.y
                anchors { top: parent.top; topMargin: Theme.pad; horizontalCenter: parent.horizontalCenter }
            }
            // Disconnected glyph under the start zone; the label does not fit a bar this thin.
            Loader {
                anchors { top: startCol.bottom; topMargin: Theme.gap; horizontalCenter: parent.horizontalCenter }
                active: bar.stale && bar.primary
                sourceComponent: Text {
                    color: Theme.accent
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: "⊘"
                }
            }
            ZoneColumn {
                id: centerCol
                owner: bar
                pieces: bar.piecesOf(bar.zones.center || [])
                anchors.centerIn: parent
            }
            ZoneHost {
                id: endBtn
                owner: bar
                entry: vl.endButton ? vl.endAll[vl.endAll.length - 1] : ({})
                anchors { bottom: parent.bottom; bottomMargin: Theme.pad; horizontalCenter: parent.horizontalCenter }
            }

            // ---- the end column's fit ----
            // The room between the center's lower edge (with a gap) and the bar's end (with the bottom margin); the end
            // button's room is not the column's.
            readonly property real endButtonH: endBtn.visible ? bar.barH + Theme.pad : 0
            readonly property real columnAvail: height / 2 - centerCol.height / 2 - Theme.gap - Theme.pad - endButtonH
            // The marker's height is measured on a fixed text: the marker's own text depends on the fit (a loop otherwise).
            TextMetrics { id: markM; text: "+0"; font.pixelSize: Theme.fsCaption; font.family: Theme.fam(text, Theme.families) }
            // The slots of the end column's modules, in order, as each reports them (plain lists, set on the next turn: a
            // binding that reads the hosts while the fit changes their loading would loop).
            property var slots: []
            property var fits: []
            property int fit: 0
            readonly property int hiddenN: slots.length - fit
            function refit() {
                var all = [], per = []
                for (var i = 0; i < endRep.count; i++) {
                    var h = endRep.itemAt(i)
                    var s = h ? h.slotHeights : []
                    per.push(s.length)
                    for (var j = 0; j < s.length; j++) all.push(s[j])
                }
                var f = fitCount(all, columnAvail, Theme.pad, markM.height)
                var fs = [], at = 0
                for (var k = 0; k < per.length; k++) { fs.push(Math.max(0, Math.min(per[k], f - at))); at += per[k] }
                if (JSON.stringify(all) !== JSON.stringify(slots)) slots = all
                if (JSON.stringify(fs) !== JSON.stringify(fits)) fits = fs
                if (fit !== f) fit = f
                requestGeometry()
            }
            onColumnAvailChanged: Qt.callLater(refit)
            // The leading slots that fit in `avail` px, `gap` apart; when some do not, a marker of `markH` follows the last
            // one that does, so the marker is in the fit too. The end of the list hides first.
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
            Column {
                id: endCol
                anchors { bottom: parent.bottom; bottomMargin: Theme.pad + vl.endButtonH; horizontalCenter: parent.horizontalCenter }
                spacing: Theme.pad
                Repeater {
                    id: endRep
                    model: vl.endList
                    onItemAdded: Qt.callLater(vl.refit)
                    onItemRemoved: Qt.callLater(vl.refit)
                    delegate: ZoneHost {
                        required property var modelData
                        required property int index
                        owner: bar
                        entry: modelData
                        anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
                        fitSlots: index < vl.fits.length ? vl.fits[index] : 0
                        onSlotHeightsChanged: Qt.callLater(vl.refit)
                    }
                }
                // The count of the slots the column has no room for; it follows the last one that is shown.
                Text {
                    id: hiddenT
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    visible: vl.hiddenN > 0
                    width: bar.barH
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: "+" + vl.hiddenN
                    Accessible.role: Accessible.StaticText
                    Accessible.name: I18n.tr("frontend.bar.hidden").replace("{n}", vl.hiddenN)
                }
            }

            // Test only (KURASHI_BAR_GEOMETRY=1, frontend/test-sidebars.sh, test-bars.sh): the boxes of what this bar draws,
            // logged a moment after each change, so a test asserts the layout from the items' geometry. Without the
            // variable: no timer, no log.
            readonly property bool geometryLog: Quickshell.env("KURASHI_BAR_GEOMETRY") === "1"
            Timer { id: geoT; interval: 300; onTriggered: vl.logGeometry() }
            function requestGeometry() { if (geometryLog) geoT.restart() }
            onWidthChanged: requestGeometry()
            onHeightChanged: requestGeometry()
            Component.onCompleted: { Qt.callLater(refit); requestGeometry(); bar.zoneRoot = vl; bar.requestZones() }
            Connections {
                target: Store
                enabled: vl.geometryLog
                function onDocsChanged() { vl.requestGeometry() }
            }
            // A box in the bar's body: a rotated item (the slider) is measured by its four corners, as it is drawn.
            function boxOf(it) {
                var a = it.mapToItem(vl, 0, 0), b = it.mapToItem(vl, it.width, 0)
                var c = it.mapToItem(vl, 0, it.height), d = it.mapToItem(vl, it.width, it.height)
                return [Math.min(a.x, b.x, c.x, d.x), Math.min(a.y, b.y, c.y, d.y),
                    Math.max(a.x, b.x, c.x, d.x), Math.max(a.y, b.y, c.y, d.y)].map(v => Math.round(v)).join(" ")
            }
            function shownOf(it) {
                if (!it) return false
                for (var p = it; p; p = p.parent) if (!p.visible) return false
                return true
            }
            function hostsOf(item, out) {
                if (!item) return out
                if (item.mid !== undefined && item.slotHeights !== undefined && item.geo !== undefined) { out.push(item); return out }
                var ch = item.children
                for (var i = 0; i < ch.length; i++) hostsOf(ch[i], out)
                return out
            }
            function logGeometry() {
                var trayHost = null
                for (var t = 0; t < endRep.count; t++) { var th = endRep.itemAt(t); if (th && th.mid === "tray") trayHost = th }
                var trayN = trayHost && trayHost.item ? trayHost.item.items.length : 0
                var trayShown = trayHost && trayHost.item ? trayHost.item.shownN : 0
                var out = ["BARGEO bar 0 0 " + Math.round(vl.width) + " " + Math.round(vl.height)]
                out.push("BARGEO fit " + fit + " hidden " + hiddenN + " trays " + trayN + " shown " + trayShown)
                function add(name, it) { if (shownOf(it)) out.push("BARGEO " + name + " " + boxOf(it)) }
                var hosts = hostsOf(vl, [])
                for (var i = 0; i < hosts.length; i++) {
                    var g = hosts[i].geo()
                    for (var j = 0; j < g.length; j++) add(g[j][0], g[j][1])
                }
                add("more", hiddenT)
                for (var k = 0; k < out.length; k++) console.log(out[k])
            }
        }
    }
}
