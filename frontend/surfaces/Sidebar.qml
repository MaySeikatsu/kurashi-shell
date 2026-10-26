import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/sidebar"
import "../components/island"

// An edge sidebar (cards W29, W44; docs/ux/sidebar.md, docs/ux/layout.md): `side` left or right. Where it stands and how it
// meets its neighbours comes from `runtime.layout` (`sidebars.<side>`: draw, visibility, width, inset, span, joins, radius;
// `edges.<side>.holder`), never re-derived here (rule 1). Per output (each output's layout names its own visibility):
// - `hidden` (default): open while runtime.ui.sidebar names its side (key, bar button, `sidebar.toggle`,
//   `layout.toggle {target: "sidebar:<side>"}` — row 486), on runtime.ui.sidebar_output, else the focused output, latched
//   while open; one at a time with the Stage's panels and the launcher (the daemon decides). While open its window takes
//   the usable area's input: a click outside the column closes it (I152; niri has no focus grab for layer surfaces).
// - `hover` (point 14): the shared edge strip on its side (EdgeReveal, the dwell); it goes 400 ms after the pointer has
//   left the column, never while it holds the keyboard or is being resized. A key still opens it as above.
// - `always`: pinned open; it keeps its zone when the layout names it the edge's `holder` (windows tile beside it).
// - `empty_desktop`: shown while the output's active workspace has no window, else as `hover`.
// No window while closed (0 frames, no subscription of its sections: Ma).
// Draw (K71): dynamic = flush to its side from what stands on the top edge to what stands on the bottom one, concave
// fillets of `radius` where it meets a bar or the frame's band (ColumnShape, the island's neck turned to the neighbour);
// connected = the same with straight joins (radius 0); floating = inset by the gap on every side, every corner rounded,
// the look's chrome. Motion (K71, user decision; supersedes W34's grow-from-the-button): the column slides in from its
// screen edge in every mode, its fillets and content with it, on the theme's spring (interruptible: a toggle mid-way turns
// it round with its velocity; `Theme.springOn` false cuts). It never passes its rest: the free end stops at the screen's
// edge. Resize (point 12): an 8 px grip along the inner edge, live while dragging, written on release as
// `sidebar.<side>.width` (one undo step); double-click resets it; Ctrl+Left/Right by 10 px while the column has focus.
Scope {
    id: sb
    required property string side            // "left" | "right"
    // shell.qml's focused output, read when the sidebar opens without a named output.
    property var focusedScreen: null

    // One refcounted subscription while the shell runs (the bars and the frame hold it too): visibility decides whether a
    // column exists at all.
    Watch { doc: "runtime.layout" }
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool toggled: ui.sidebar === side
    readonly property string wantOutput: toggled && typeof ui.sidebar_output === "string" ? ui.sidebar_output : ""
    // The output a toggle opened it on, latched while open (the daemon may name another while it is open: then that one).
    property string toggledOn: ""
    function screenNamed(n) {
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) if (s[i].name === n) return s[i]
        return null
    }
    function pickName() {
        var s = wantOutput !== "" ? screenNamed(wantOutput) : null
        if (s === null) s = focusedScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
        return s ? s.name : ""
    }
    onToggledChanged: toggledOn = toggled ? pickName() : ""
    onWantOutputChanged: if (toggled) toggledOn = pickName()
    Component.onCompleted: if (toggled) toggledOn = pickName()

    // The sidebar keys are global (`sidebar.<side>.*`).
    BarConfig { id: cfg; screen: null }
    readonly property string widthKey: "sidebar." + side + ".width"
    readonly property var widthEntry: cfg.entry(widthKey)
    // A layer above the user's sets the width: the grip is inert and says by whom (Shōjiki).
    readonly property string widthForcedBy: widthEntry && widthEntry.forced_by ? String(widthEntry.forced_by) : ""
    readonly property var sections: {
        var v = cfg.valueOf("sidebar." + side + ".sections", side === "left" ? ["mod:ai:ai"]
            : ["header", "toggles", "sliders", "notifications", "calendar"])
        return Array.isArray(v) ? v.filter(function (s) { return typeof s === "string" && s !== "" }) : []
    }
    readonly property bool instant: !Theme.springOn
    readonly property bool geometryLog: Quickshell.env("KURASHI_SIDEBAR_GEOMETRY") === "1"
    readonly property bool traceLog: Quickshell.env("KURASHI_SIDEBAR_TRACE") === "1"
    // Test only (frontend/test-texture.sh, the carried sheet): the column holds at this slide progress instead of moving.
    readonly property real holdP: Quickshell.env("KURASHI_SIDEBAR_HOLD") ? Number(Quickshell.env("KURASHI_SIDEBAR_HOLD")) : -1
    // Test only (frontend/test-sidebars.sh): KURASHI_SIDEBAR_FREEZE names a file read at each open and close; "open 120"
    // holds the slide still 120 ms after it starts (for a shot), for 1.5 s, and logs it. Without the variable no file is
    // touched.
    readonly property string freezePath: Quickshell.env("KURASHI_SIDEBAR_FREEZE") || ""
    FileView { id: freezeFile; blockAllReads: true; printErrors: false }
    function readFreeze(phase) {
        if (freezePath === "") return null
        // A new path each time: FileView reads it afresh (a reload of the same path kept the first text).
        freezeFile.path = ""
        freezeFile.path = freezePath
        freezeFile.reload()
        freezeFile.waitForJob()
        var t = String(freezeFile.text() || "").trim().split(/\s+/)
        if (geometryLog) console.log("sidebar-freeze-read '" + t.join(" ") + "' " + phase)
        if (t.length >= 2 && t[0] === phase) return { ms: Number(t[1]), hold: t.length >= 3 ? Number(t[2]) : 1500 }
        return null
    }
    function num(v, d) { return typeof v === "number" && !isNaN(v) ? v : d }

    Variants {
        model: Quickshell.screens
        Scope {
            id: col
            required property var modelData
            readonly property var scr: modelData
            readonly property string out: scr ? scr.name : ""
            readonly property int sw: scr ? scr.width : 1920
            readonly property int sh: scr ? scr.height : 1080

            // ---- the layout of this side on this output ----
            readonly property var lay: ShellLayout.of(out)
            readonly property var sl: (lay.sidebars || {})[sb.side] || ({})
            readonly property var edges: lay.edges || ({})
            readonly property string vis: typeof sl.visibility === "string" ? sl.visibility
                : String(cfg.valueOf("sidebar." + sb.side + ".visibility", "hidden"))
            readonly property string draw: typeof sl.draw === "string" ? sl.draw : "dynamic"
            readonly property bool floating: draw === "floating"
            readonly property int inset: sb.num(sl.inset, floating ? ShellLayout.gap : 0)
            readonly property int spanStart: sb.num((sl.span || {}).start, floating ? ShellLayout.gap : 0)
            readonly property int spanEnd: sb.num((sl.span || {}).end, floating ? ShellLayout.gap : 0)
            readonly property string joinStart: !floating && sl.joins ? String(sl.joins.start || "") : ""
            readonly property string joinEnd: !floating && sl.joins ? String(sl.joins.end || "") : ""
            readonly property int joinR: Math.max(0, sb.num(sl.radius, floating ? 0 : ShellLayout.joinRadius))
            // A docked bar on the sidebar's own side: its outer side meets the bar (one sheet).
            readonly property var sideEdge: edges[sb.side] || ({})
            readonly property bool sideBar: !floating && sideEdge.bar === true && sideEdge.draw !== "floating"
            readonly property bool holder: sideEdge.holder === "sidebar"
            readonly property int reserve: holder ? sb.num(sideEdge.reserve, 0) : 0
            // A bar the column meets at an end or along its side (the rule's opening, SidebarGeom; the log's `bar`).
            readonly property string barEdge: joinStart.indexOf("bar:") === 0 ? joinStart.substring(4)
                : (joinEnd.indexOf("bar:") === 0 ? joinEnd.substring(4) : (sideBar ? sb.side : "none"))
            function zoneOf(e) { var x = edges[e] || {}; return x.holder && x.holder !== "none" ? sb.num(x.reserve, 0) : 0 }
            // A change of draw mode while the column is out moves its edges and its fillets (the radius grows or goes)
            // over `motion.std`, never a jump (docs/ux/layout.md "Motion"); cut without motion. Nothing runs at rest.
            readonly property bool morphs: held && Theme.springOn
            property real aInset: inset
            property real aStart: spanStart
            property real aEnd: spanEnd
            property real aR: joinR
            Behavior on aInset { enabled: col.morphs; NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutCubic } }
            Behavior on aStart { enabled: col.morphs; NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutCubic } }
            Behavior on aEnd { enabled: col.morphs; NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutCubic } }
            Behavior on aR { enabled: col.morphs; NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutCubic } }

            // ---- width ----
            readonly property int maxW: Math.max(320, Math.min(640, sw - inset - Theme.gap))
            function clampW(w) { return Math.max(320, Math.min(maxW, Math.round(w))) }
            // Multiples of 10 from 320 (the schema's step; an off-step value is refused).
            function stepW(w) { return Math.max(320, Math.min(maxW - (maxW - 320) % 10, 320 + Math.round((w - 320) / 10) * 10)) }
            readonly property int docW: clampW(sb.num(sl.width, Number(cfg.valueOf(sb.widthKey, 420)) || 420))
            // While dragged (or written and not yet answered), the width the user is giving it.
            property int liveW: -1
            property int pendingW: -1
            onDocWChanged: if (pendingW >= 0 && docW === pendingW) { pendingW = -1; if (!resizing) liveW = -1 }
            readonly property int colW: liveW >= 0 ? clampW(liveW) : docW

            // ---- when it is out ----
            readonly property bool toggledHere: sb.toggled && sb.toggledOn === out
            readonly property bool pinned: vis === "always"
            readonly property bool emptyMode: vis === "empty_desktop"
            Watch { doc: "svc.workspaces"; active: col.emptyMode }
            readonly property bool emptyDesk: {
                if (!emptyMode) return false
                var t = (Store.docs["svc.workspaces"] || {}).tasks
                if (!t) return false
                var l = t[out] || t["*"]
                return Array.isArray(l) && l.length === 0
            }
            readonly property bool hoverOn: vis === "hover" || (emptyMode && !emptyDesk)
            property bool pointerIn: false
            property bool focusHeld: false
            property bool resizing: false
            EdgeReveal {
                id: reveal
                screen: col.scr
                edge: sb.side
                key: "sidebar:" + sb.side
                enabled: col.hoverOn && !col.toggledHere && col.out !== ""
                from: col.spanStart
                to: col.sh - col.spanEnd
                holdIn: col.pointerIn || col.focusHeld || col.resizing
            }
            readonly property bool wanted: pinned || (emptyMode && emptyDesk) || toggledHere || reveal.revealed
            // The window exists: out, sliding in or out.
            property bool held: false

            // ---- the slide: 0 = behind its screen edge, 1 = at rest ----
            property real p: 0
            property bool gate: false
            property bool frozen: false
            property bool expanding: true
            readonly property bool holding: sb.holdP >= 0 && held
            readonly property bool springing: held && !gate && !sb.instant && !frozen && !holding
            Behavior on p {
                enabled: col.springing
                SpringAnimation {
                    id: spring
                    // Stiffer than the island's: a column a screen tall must not creep in its last tenth.
                    spring: Theme.spring * (col.expanding ? 1.25 : 1.6)
                    damping: Math.min(1, Theme.damping * (col.expanding ? 1 : 1.25))
                    epsilon: 0.002
                    onRunningChanged: col.settled()
                }
            }
            onWantedChanged: drive()
            Component.onCompleted: if (wanted) drive()
            function drive() {
                if (holding || sb.holdP >= 0) {
                    if (wanted) {
                        held = true; gate = false; p = Math.max(0, Math.min(1, sb.holdP))
                        // (test-texture.sh reads how far the held column stands from its rest.)
                        if (sb.geometryLog) console.log("sidebar-hold " + sb.side + " " + out + " p=" + p.toFixed(3) + " off=" + Math.round(off))
                    }
                    else { held = false; p = 0 }
                    return
                }
                var fz = sb.readFreeze(wanted ? "open" : "close")
                freezeMs = fz ? fz.ms : -1
                freezeHoldMs = fz ? fz.hold : 1500
                if (wanted) {
                    if (!held) { frozen = false; p = 0; gate = !sb.instant; held = true }
                    if (sb.instant) { p = 1; settled() }
                    else if (!gate) toward(1)
                } else if (held) {
                    gate = false
                    if (sb.instant) { p = 0; held = false }
                    else { toward(0); gone() }
                }
            }
            function toward(v) {
                expanding = v > 0.5
                if (frozen) { unfreezeTimer.stop(); frozen = false }
                p = v
                if (freezeMs >= 0) freezeTimer.restart()
            }
            onPChanged: {
                if (sb.traceLog) console.log("sb-trace " + Date.now() + " " + sb.side + " p=" + p.toFixed(3) + " exp=" + expanding)
                gone()
            }
            // Slid back behind its edge: the window goes.
            function gone() {
                if (wanted || !held || holding || p > 0.002) return
                freezeTimer.stop(); unfreezeTimer.stop(); frozen = false
                held = false
                p = 0
            }
            function settled() {
                if (spring.running) return
                if (sb.geometryLog && held && wanted && !frozen && p === 1) console.log("sidebar-rest " + sb.side + " " + out + " p=1.000")
            }
            property int freezeMs: -1
            property int freezeHoldMs: 1500
            Timer {
                id: freezeTimer
                interval: Math.max(1, col.freezeMs)
                onTriggered: {
                    console.log("sidebar-frozen " + sb.side + " " + (col.expanding ? "open" : "close") + " " + col.freezeMs
                        + " p=" + col.p.toFixed(3))
                    // Held where it is (the Behavior off, the value written back), not paused: a resumed SpringAnimation
                    // integrates the paused time at once.
                    col.frozen = true
                    col.freezeMs = -1
                    var v = col.p
                    col.p = v
                    unfreezeTimer.start()
                }
            }
            Timer {
                id: unfreezeTimer
                interval: Math.max(1, col.freezeHoldMs)
                onTriggered: { col.frozen = false; col.toward(col.wanted ? 1 : 0) }
            }
            // How far it stands from its rest, toward its screen edge (never past the rest: the free end stops there).
            readonly property real travel: colW + inset + Theme.gap + Theme.softR + Math.abs(Theme.sinkX) + 4
            readonly property real off: Math.max(0, 1 - p) * travel

            // ---- resize ----
            function writeWidth(w) {
                var v = stepW(w)
                liveW = v
                if (v === docW) { liveW = -1; return }
                pendingW = v
                Store.apply([{ set: sb.widthKey, value: v }], function (errors) {
                    if (!errors) return
                    col.pendingW = -1
                    col.liveW = -1
                    if (sb.geometryLog) console.log("sidebar-width refused " + JSON.stringify(errors))
                })
                if (sb.geometryLog) console.log("sidebar-width " + sb.side + " " + v)
            }
            function resetWidth() {
                liveW = -1
                pendingW = -1
                Store.apply([{ reset: sb.widthKey }], function (errors) {
                    if (errors && sb.geometryLog) console.log("sidebar-width reset refused " + JSON.stringify(errors))
                })
                if (sb.geometryLog) console.log("sidebar-width " + sb.side + " reset")
            }
            // Ctrl+Left/Right: 10 px a press, written after a short pause (one undo step for a run of presses).
            function nudge(dir) {
                if (sb.widthForcedBy !== "") return
                liveW = clampW(colW + dir * 10)
                keyWrite.restart()
            }
            Timer { id: keyWrite; interval: 450; onTriggered: col.writeWidth(col.colW) }

            // A column that holds its side's zone is mapped after the top and bottom bars that hold theirs: the compositor
            // places a holder inside the zones of the holders mapped before it (W43-frame's probe), and the horizontal bars
            // own the corners (K71) — mapped after the column, a bottom bar came out between the two pinned columns' zones
            // (measured: 420..1500 of 1920). A bar that turns up later takes the column down until it is on screen.
            readonly property bool barsFirst: {
                if (!holder) return true
                var es = ["top", "bottom"]
                for (var i = 0; i < es.length; i++) {
                    var x = edges[es[i]] || {}
                    if (x.bar !== true || x.holder !== "bar" || !(x.reserve > 0)) continue
                    var b = IslandGeom.barOf(out, es[i])
                    if (!b || !b.mapped) return false
                }
                return true
            }
            LazyLoader {
                active: col.held && col.barsFirst
                PanelWindow {
                    id: win
                    screen: col.scr
                    // A toggled column (hidden mode) takes the usable area's input: a click outside closes it.
                    readonly property bool catcher: col.toggledHere && !col.pinned
                    anchors { top: true; bottom: true; left: sb.side === "left"; right: sb.side === "right" }
                    // The column's part of the output: as wide as the widest column (a drag never resizes the window, so
                    // the pointer's place stays put), the whole width while it catches clicks.
                    readonly property real boxW: Math.min(col.sw, 640 + col.inset + col.joinR + Theme.gap + Theme.softR
                        + Math.abs(Theme.sinkX) + 12)
                    implicitWidth: catcher ? col.sw : Math.ceil(boxW)
                    // K71: only the edge's holder keeps the zone (windows tile beside a pinned column); every other
                    // column ignores zones and stands where the layout says, from the screen's edges.
                    exclusionMode: col.holder ? ExclusionMode.Normal : ExclusionMode.Ignore
                    // Only a holder sets the zone: setting `exclusiveZone` at all turns the window to ExclusionMode.Normal
                    // (measured: a column with `exclusiveZone: 0` was placed below the top bar's zone).
                    Binding on exclusiveZone { when: col.holder; value: col.reserve; restoreMode: Binding.RestoreNone }
                    color: "transparent"
                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.namespace: "kurashi-sidebar"
                    WlrLayershell.keyboardFocus: col.wanted ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                    mask: Region {
                        item: catchArea
                        Region { item: inputRect }
                        Region { item: grip }
                    }
                    BackgroundEffect.blurRegion: Region { item: shapeRect }

                    readonly property string outName: col.out
                    // K59: this window's tile set, shared by its reliefs, and the pointer light's sensor. K61: the content
                    // rides with the column; the column's own relief carries its sheet (`carry`), the window none.
                    property var tileSheet: tilesLoader.item
                    readonly property point sheetCarry: Qt.point(0, 0)
                    Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
                    LightSense {}
                    // A holder sits inside the zones of the holders the compositor placed before it (W43-frame's probe):
                    // its top on the output, as Light counts the other windows' zones. Every other column starts at the
                    // screen's top.
                    readonly property real offTop: col.holder ? Light.zoneOf(win, "top") : 0
                    // Where the usable area starts in this window (Placement reports a mod panel's rect from there).
                    readonly property point placementOrigin: Qt.point(Math.max(0, col.zoneOf(sb.side) - (col.holder ? col.reserve : 0)),
                        col.zoneOf("top") - offTop)
                    readonly property string zoneKey: [col.out, sb.side, col.holder ? col.reserve : 0].join("|")
                    onZoneKeyChanged: Light.setZone(win, col.out, sb.side, col.holder ? col.reserve : 0)

                    // ---- geometry: the canonical frame is the window's side part, `boxW` wide, its outer side at the
                    // screen's edge (mirrored for the left side); y as the window's ----
                    readonly property real y0: col.aStart - offTop
                    readonly property real y1: col.sh - col.aEnd - offTop
                    readonly property real rx1: boxW - col.aInset
                    readonly property real rx0: rx1 - col.colW
                    readonly property real shX0: rx0 + col.off
                    readonly property real shX1: rx1 + col.off
                    readonly property bool openT: col.joinStart !== ""
                    readonly property bool openB: col.joinEnd !== ""
                    readonly property bool openO: !col.floating
                    // What may be drawn: never over the neighbours a joined column meets (their fill is translucent); a
                    // floating column slides out from behind the screen's edge.
                    readonly property real clipX1: col.floating ? boxW : rx1
                    readonly property real clipY0: openT ? y0 : 0
                    readonly property real clipY1: openB ? y1 : height
                    // Canonical → window.
                    function realX(x0c, x1c) { return sb.side === "left" ? boxW - x1c : width - boxW + x0c }
                    readonly property rect restRect: Qt.rect(realX(rx0, rx1), y0, col.colW, y1 - y0)
                    // K61: the column's material comes with it (output axes).
                    readonly property point shapeCarry: Qt.point((sb.side === "left" ? -1 : 1) * col.off, 0)

                    function logGeom() {
                        if (!sb.geometryLog) return
                        var ox = sb.side === "left" ? 0 : col.sw - width
                        console.log("sidebar-geom " + col.out + " " + sb.side + " " + (col.floating ? "floating" : "panel")
                            + " win " + Math.round(width) + " " + Math.round(height) + " frame " + Math.round(ox + restRect.x)
                            + "," + Math.round(offTop + restRect.y) + "," + Math.round(restRect.width) + "," + Math.round(restRect.height)
                            + " bar " + col.barEdge + " " + Theme.barH + " gap " + Theme.gap + " draw " + col.draw + " vis " + col.vis
                            + " joins " + (col.joinStart || "-") + "," + (col.joinEnd || "-") + " radius " + col.joinR
                            + " holder " + (col.holder ? col.reserve : 0) + " sections " + sb.sections.join(","))
                    }
                    onRestRectChanged: logGeom()
                    onWidthChanged: logGeom()
                    Component.onCompleted: {
                        Light.setZone(win, col.out, sb.side, col.holder ? col.reserve : 0)
                        if (sb.geometryLog) console.log("sidebar-window up " + sb.side + " " + col.out)
                        logGeom()
                    }
                    Component.onDestruction: {
                        Light.setZone(win, "", sb.side, 0)
                        SidebarGeom.clear(outName, sb.side)
                        col.focusHeld = false
                        col.pointerIn = false
                        if (sb.geometryLog) console.log("sidebar-window down " + sb.side + " " + outName)
                    }
                    // At rest under (or beside) a ruled bar, the span of the bar's edge the column and its fillets cover,
                    // for the bar to leave its rule out there (SidebarGeom); withdrawn as soon as it moves.
                    readonly property bool atRest: col.wanted && !col.gate && !col.frozen && col.p === 1 && !spring.running
                    // Row 521: one opening per bar the column meets — the bar at its start (top), the one at its end
                    // (bottom) and a docked bar on its own side — each `[edge, from, to]` along that bar's edge.
                    readonly property string openingsKey: {
                        if (!atRest || !shape.ruled) return ""
                        var ox = sb.side === "left" ? 0 : col.sw - width
                        var out = []
                        function across(edge, f) {
                            var a = ox + realX(rx0 - f, rx1)
                            out.push([edge, Math.round(a), Math.round(a + col.colW + f)])
                        }
                        if (col.joinStart === "bar:top") across("top", shape.fTi)
                        if (col.joinEnd === "bar:bottom") across("bottom", shape.fBi)
                        if (col.sideBar)
                            out.push([sb.side, Math.round(offTop + y0 - shape.fOt), Math.round(offTop + y1 + shape.fOb)])
                        return JSON.stringify(out)
                    }
                    onOpeningsKeyChanged: {
                        SidebarGeom.clear(outName, sb.side)
                        var list = openingsKey !== "" ? JSON.parse(openingsKey) : []
                        for (var i = 0; i < list.length; i++) SidebarGeom.set(outName, sb.side, list[i][0], list[i][1], list[i][2])
                        if (sb.geometryLog) console.log("sidebar-opening " + sb.side + " " + (list.length > 0
                            ? list.map(function (o) { return o[0] + ":" + o[1] + "," + o[2] }).join(" ") : "none"))
                    }
                    // The slide starts on the window's first presented frame (as the Stage's), so it is never skipped.
                    Connections {
                        target: shapeRect.Window.window
                        function onFrameSwapped() {
                            if (!col.gate) return
                            col.gate = false
                            if (col.wanted) col.toward(1)
                        }
                    }

                    // The column's body in window coordinates: the input region, the blur, what counts as inside.
                    Item {
                        id: shapeRect
                        x: win.realX(win.shX0, win.shX1)
                        y: win.y0
                        width: col.colW
                        height: Math.max(0, win.y1 - win.y0)
                        HoverHandler { id: shapeHover; onHoveredChanged: col.pointerIn = hovered || gripHover.hovered }
                    }
                    // The column's input: all of it, but the 2 px on the screen's edge while it came out on hover (the
                    // shared strip keeps the pointer there: EdgeReveal, row 524).
                    Item {
                        id: inputRect
                        readonly property int cut: reveal.cutFor(col.inset)
                        x: shapeRect.x + (sb.side === "left" ? cut : 0)
                        y: shapeRect.y
                        width: Math.max(0, shapeRect.width - cut)
                        height: shapeRect.height
                    }
                    // While a toggle holds it open: the usable area takes clicks (the catcher; the bars keep theirs).
                    Item {
                        id: catchArea
                        x: win.catcher ? col.zoneOf("left") : 0
                        y: win.catcher ? col.zoneOf("top") - win.offTop : 0
                        width: win.catcher ? Math.max(0, win.width - col.zoneOf("left") - col.zoneOf("right")) : 0
                        height: win.catcher ? Math.max(0, col.sh - col.zoneOf("top") - col.zoneOf("bottom")) : 0
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: win.catcher && col.wanted
                        acceptedButtons: Qt.AllButtons
                        onPressed: ev => {
                            if (ev.x >= shapeRect.x - 4 && ev.x < shapeRect.x + shapeRect.width + 4 && ev.y >= shapeRect.y
                                && ev.y < shapeRect.y + shapeRect.height) {
                                ev.accepted = false
                                return
                            }
                            if (sb.geometryLog) console.log("sidebar-outside " + sb.side + " " + Math.round(ev.x) + "," + Math.round(ev.y))
                            Store.act("sidebar.close")
                        }
                    }

                    // Everything the column draws, cut where it meets its neighbours.
                    Item {
                        id: clipper
                        x: win.realX(0, win.clipX1)
                        y: win.clipY0
                        width: win.clipX1
                        height: Math.max(0, win.clipY1 - win.clipY0)
                        clip: true

                        // The shape, its shadow and its relief mask, in the canonical frame.
                        Item {
                            id: box
                            x: (sb.side === "left" ? 0 : win.width - win.boxW) - clipper.x
                            y: -clipper.y
                            width: win.boxW
                            height: win.height
                            transform: Scale { xScale: sb.side === "left" ? -1 : 1; origin.x: win.boxW / 2 }
                            SoftShadow {
                                visible: col.floating && shape.shown
                                x: shape.bodyRect.x
                                y: shape.bodyRect.y
                                width: shape.bodyRect.width
                                height: shape.bodyRect.height
                                radius: Theme.rLg
                                // The column is drawn mirrored for the left side (the Scale above): mirror the shadow's x
                                // back so it falls the way the light says on both sides (K67, row 421).
                                mirror: sb.side === "left" ? -1 : 1
                            }
                            ColumnShape {
                                id: shape
                                anchors.fill: parent
                                x0: win.shX0
                                x1: win.shX1
                                y0: win.y0
                                y1: win.y1
                                openT: win.openT
                                openB: win.openB
                                openO: win.openO
                                // A join with the screen's edge is flush, without a fillet; a bar or the band: the
                                // layout's radius (0 = connected, a straight join).
                                neckT: col.joinStart === "edge" ? 0 : col.aR
                                neckB: col.joinEnd === "edge" ? 0 : col.aR
                                neckO: col.sideBar ? col.aR : 0
                                squareOuter: !col.floating
                                flipX: sb.side === "left"
                                // Where the neighbour rules its edge (line chrome; floating keycap groups draw no strip).
                                ruled: !col.floating && Theme.outlineW > 0 && !(Theme.groups && Theme.lifted)
                                chrome: col.floating
                                // Joined, the column takes its neighbour's colour (one sheet); a free column the panel's.
                                fill: col.floating ? Theme.panel : Theme.surfaceAlpha
                            }
                            // The shape's fill as a mask for its relief (I168): drawn only into `shapeMask`'s texture, which
                            // is redrawn when the path changes (while the column moves) and never at rest.
                            Shape {
                                id: maskShape
                                visible: reliefBox.on
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeWidth: -1
                                    strokeColor: "transparent"
                                    fillColor: "white"
                                    PathSvg { path: reliefBox.on ? shape.fillPath : "" }
                                }
                            }
                        }
                        // K59, K61: the column's material, clipped to the shape's fill (fillets included), under the
                        // content (over it with `texture.text`); carried with the column.
                        Item {
                            id: reliefBox
                            readonly property bool on: Theme.texShell && shape.shown
                            readonly property point carry: win.shapeCarry
                            z: Theme.texText ? 2 : 0
                            visible: on
                            x: box.x
                            y: box.y
                            width: win.boxW
                            height: win.height
                            transform: Scale { xScale: sb.side === "left" ? -1 : 1; origin.x: win.boxW / 2 }
                            Loader {
                                anchors.fill: parent
                                active: reliefBox.on
                                sourceComponent: Relief {
                                    anchors.fill: parent
                                    mask: shapeMask
                                    // (not `win.…` here: Relief has a `win` of its own)
                                    carry: reliefBox.carry
                                }
                            }
                        }

                        // The content rides with the column. The column's one keyboard focus holder: Esc backs out of a
                        // page first, then closes (a toggled column) or lets go (a hover one).
                        FocusScope {
                            id: content
                            z: 1
                            x: shapeRect.x - clipper.x + Theme.pad
                            y: shapeRect.y - clipper.y + Theme.pad
                            width: col.colW - 2 * Theme.pad
                            height: shapeRect.height - 2 * Theme.pad
                            focus: true
                            onActiveFocusChanged: col.focusHeld = activeFocus
                            Keys.onPressed: event => {
                                var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                                if (ctrl && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                                    // The inner edge moves: left widens a right column, right widens a left one.
                                    var widen = (event.key === Qt.Key_Left) === (sb.side === "right")
                                    col.nudge(widen ? 1 : -1)
                                    event.accepted = true
                                    return
                                }
                                if (event.key !== Qt.Key_Escape) return
                                if (!(colLoader.item && colLoader.item.back && colLoader.item.back())) {
                                    if (col.toggledHere) Store.act("sidebar.close")
                                    else if (reveal.revealed) reveal.revealed = false
                                }
                                event.accepted = true
                            }
                            // A toggled column takes the keyboard; one that came out on hover or is pinned waits for a
                            // click (a pointer resting on the edge must not take the app's focus).
                            Component.onCompleted: if (col.toggledHere) Qt.callLater(function () { content.forceActiveFocus() })
                            Accessible.role: Accessible.Pane
                            Accessible.name: I18n.tr(sb.side === "left" ? "sidebar.a11y.left" : "sidebar.a11y.right")

                            Loader {
                                id: colLoader
                                anchors.fill: parent
                                focus: true
                                sourceComponent: sb.side === "left" ? leftC : rightC
                            }
                        }
                    }
                    // Parked outside the window, as TileSheet's copies: a texture provider needs its paint node.
                    ShaderEffectSource {
                        id: shapeMask
                        x: -100000
                        width: win.boxW
                        height: win.height
                        sourceItem: reliefBox.on ? maskShape : null
                        hideSource: true
                        live: false
                    }
                    Connections {
                        target: reliefBox.on ? shape : null
                        function onFillPathChanged() { shapeMask.scheduleUpdate() }
                    }

                    // The resize grip (point 12): 8 px along the inner edge, half over the column.
                    Item {
                        id: grip
                        readonly property bool inert: sb.widthForcedBy !== ""
                        x: (sb.side === "right" ? shapeRect.x : shapeRect.x + shapeRect.width) - 4
                        y: shapeRect.y
                        width: 8
                        height: shapeRect.height
                        visible: col.wanted
                        Accessible.role: Accessible.Grip
                        Accessible.name: I18n.tr("sidebar.a11y.grip")
                        Accessible.description: inert ? I18n.tr("sidebar.resize.forced").replace("{by}", sb.widthForcedBy)
                            : I18n.tr("sidebar.resize.hint").replace("{w}", col.colW)
                        // The edge lights while the pointer is on it or it is dragged (where the grip is, not colour alone:
                        // the cursor says it too).
                        Rectangle {
                            visible: !grip.inert && (gripHover.hovered || drag.pressed)
                            x: 3
                            width: 2
                            height: parent.height
                            radius: 1
                            color: Theme.accent
                            opacity: drag.pressed ? 0.9 : 0.55
                        }
                        HoverHandler { id: gripHover; onHoveredChanged: col.pointerIn = hovered || shapeHover.hovered }
                        MouseArea {
                            id: drag
                            anchors.fill: parent
                            enabled: !grip.inert
                            cursorShape: Qt.SplitHCursor
                            preventStealing: true
                            property real startX: 0
                            property int startW: 0
                            onPressed: ev => {
                                startX = mapToItem(null, ev.x, 0).x
                                startW = col.colW
                                col.resizing = true
                                col.liveW = startW
                            }
                            onPositionChanged: ev => {
                                if (!pressed) return
                                var dx = mapToItem(null, ev.x, 0).x - startX
                                if (Math.abs(dx) >= 2) moved = true
                                if (moved) col.liveW = col.clampW(startW + (sb.side === "right" ? -dx : dx))
                            }
                            // A press that did not move (one half of a double click) writes nothing.
                            property bool moved: false
                            onReleased: {
                                col.resizing = false
                                if (sb.geometryLog) console.log("sidebar-grip release moved=" + moved + " w=" + col.liveW)
                                if (moved && !resetting) col.writeWidth(col.liveW)
                                else if (!resetting) col.liveW = -1
                                moved = false
                                resetting = false
                            }
                            onCanceled: { col.resizing = false; col.liveW = -1; moved = false; resetting = false }
                            property bool resetting: false
                            onDoubleClicked: { resetting = true; col.resizing = false; col.resetWidth() }
                        }
                    }
                }
            }
        }
    }
    Component {
        id: rightC
        RightColumn { sections: sb.sections; outName: QsWindow.window && QsWindow.window.outName !== undefined ? QsWindow.window.outName : "" }
    }
    Component {
        id: leftC
        LeftColumn { tabs: sb.sections }
    }
}
