import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/island"
import "../components/sidebar"

// An edge sidebar (card W29, docs/ux/sidebar.md): `side` left or right, open while runtime.ui.sidebar names it (the daemon
// decides, one at a time with the Stage's panels and the launcher). One layer surface on the asking output
// (runtime.ui.sidebar_output, else the focused one, latched while open); closed = no window at all, 0 frames, no
// subscription (Ma). The window is anchored to all four edges with exclusive zone 0, so the compositor fits it to the
// output's usable area: it stops at a bar on any side (copied from ii `modules/ii/sidebarRight/SidebarRight.qml`;
// shellseikatsu's own arithmetic for the bar's size broke under side bars — its docs/BUGS.md). The column lies on its side.
// `sidebar.<side>.draw` (K71): dynamic/connected = flush, outer corners square, inner corners `radius.lg`; floating = inset by `space.sm`, every
// corner rounded, the look's chrome (ring, hard or soft shadow). Tokens only (rule 4).
// W34 (docs/ux/motion.md, "the bar reaches out"): the column is one shape (ColumnShape) that grows out of the bar's end —
// from the sidebar button's place at the bar's end, else the bar's corner — and folds back into it, width and height on
// their own springs as the island's (width leads out, height leads back; interruptible, velocity kept). Where it meets the
// bar's edge it is joined to it by concave fillets in the bar's own colour, so bar and column read as one sheet; a side
// bar on the sidebar's side: the column grows along it. The content sits where it rests, cut to the shape, and fades in
// late (out first); the column's material is carried with its leading edges (K61). `lively` (a low spring damping)
// stretches the shape as it lengthens fast and squashes it as it lands, the neck wobbling once; `calm` settles softly;
// `Theme.springOn` false cuts. While open the window takes the whole usable area's input: a click outside the column
// closes it (I152; niri has no focus grab for layer surfaces). Esc backs out of a page, then closes.
Scope {
    id: sb
    required property string side            // "left" | "right"
    // shell.qml's focused output, read when the sidebar opens without a named output.
    property var focusedScreen: null

    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool wanted: ui.sidebar === side
    readonly property string wantOutput: wanted && typeof ui.sidebar_output === "string" ? ui.sidebar_output : ""

    // The output it is on: picked when it opens, or when the daemon names another output while it is open.
    property var screen: null
    // The window exists: open, growing or folding back.
    property bool held: false
    readonly property bool instant: !Theme.springOn

    function screenNamed(n) {
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) if (s[i].name === n) return s[i]
        return null
    }
    function pick() {
        var s = wantOutput !== "" ? screenNamed(wantOutput) : null
        return s !== null ? s : (focusedScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null))
    }

    // ---- the morph: width and height progress, 0 = the origin, 1 = the column at rest ----
    property real mw: 0
    property real mh: 0
    property bool expanding: true
    // The free end has reached the far edge once: the height stays there and the spring's rebound goes into the width
    // (the column cannot overshoot past the screen's edge; it squashes instead).
    property bool landed: false
    // The height's speed (progress per second), for the stretch; measured only while it moves.
    property real vh: 0
    property real lastMh: 0
    property double lastT: 0
    // The morph starts on the first presented frame of the new window (as the Stage's), so it is never skipped.
    property bool gate: false

    // Test only (frontend/test-texture.sh, the carried sheet): the column holds at this width progress (full height,
    // flush) instead of growing.
    readonly property real holdP: Quickshell.env("KURASHI_SIDEBAR_HOLD") ? Number(Quickshell.env("KURASHI_SIDEBAR_HOLD")) : -1
    readonly property bool holding: holdP >= 0 && held
    onWantedChanged: {
        if (!wanted && holdP >= 0) { held = false; mw = 0; mh = 0; return }
        if (wanted && holdP >= 0) {
            if (!held) { screen = pick(); held = true }
            gate = false
            stopSprings()
            mh = 1
            landed = true
            mw = Math.max(0, (holdP * colW - nubW) / Math.max(1, colW - nubW))
            return
        }
        if (wanted) {
            if (!held) { screen = pick(); readOrigin(); stopSprings(); mw = 0; mh = 0; landed = false; vh = 0; gate = !instant; held = true }
            readFreeze("open")
            if (instant) { stopSprings(); mw = 1; mh = 1; landed = true; settled() }
            else if (!gate) driveTo(1)
        } else if (held) {
            gate = false
            readFreeze("close")
            if (instant) { stopSprings(); mw = 0; mh = 0; held = false }
            // (closed before its first frame: nothing moves, so it folds here)
            else { landed = false; driveTo(0); folded() }
        }
    }
    onWantOutputChanged: if (wanted && held) screen = pick()

    // The island's springs (Stage.qml): width leads on the way out, height on the way back. Behaviors, as there: a new
    // target retargets the running spring with its velocity (a standalone SpringAnimation ignored a new `to`, measured).
    readonly property bool springing: held && !gate && !instant && !frozen && !holding
    function driveTo(v) {
        expanding = v > 0.5
        if (frozen) { unfreezeTimer.stop(); frozen = false }
        mw = v
        mh = v
        if (freezeMs >= 0) freezeTimer.restart()
    }
    // The springs stand where they are while not `springing` (their Behaviors off); this drops the test freeze.
    function stopSprings() { freezeTimer.stop(); unfreezeTimer.stop(); frozen = false; vh = 0 }
    Behavior on mw {
        enabled: sb.springing
        SpringAnimation {
            id: springW
            spring: Theme.spring * (sb.expanding ? 1.3 : 1.2)
            damping: Math.min(1, Theme.damping * (sb.expanding ? 1 : 1.25))
            epsilon: 0.002
            onRunningChanged: sb.settled()
        }
    }
    Behavior on mh {
        enabled: sb.springing
        SpringAnimation {
            id: springH
            // Stiffer than the island's height on the way out: a column a screen tall must not creep in its last tenth.
            spring: Theme.spring * (sb.expanding ? 1.2 : 1.6)
            damping: Math.min(1, Theme.damping)
            epsilon: 0.002
            onRunningChanged: sb.settled()
        }
    }
    onMhChanged: {
        var t = Date.now(), dt = t - lastT
        if (springH.running && dt > 0 && dt < 100) vh = 0.5 * vh + 0.5 * (mh - lastMh) * 1000 / dt
        lastT = t
        lastMh = mh
        if (traceLog) console.log("sb-trace " + t + " mw=" + mw.toFixed(3) + " mh=" + mh.toFixed(3) + " exp=" + expanding)
        if (expanding && wanted && mh >= 1) landed = true
        folded()
    }
    onMwChanged: folded()
    // Folded back into the bar: the window goes.
    function folded() {
        if (wanted || !held || holding || mw > 0.02 || mh > 0.02) return
        stopSprings()
        held = false
        mw = 0
        mh = 0
    }
    function settled() {
        if (springW.running || springH.running) return
        vh = 0
        if (geometryLog && held && wanted && !frozen && mw === 1 && mh === 1) console.log("sidebar-rest " + side + " mw=" + mw.toFixed(3) + " mh=" + mh.toFixed(3))
    }

    // `lively` from the tokens (rule 4): a spring damped well under `calm`'s stretches and squashes; calm's does not.
    readonly property real sqK: Math.max(0, Math.min(1, (0.42 - Theme.damping) / 0.12))
    readonly property real squash: {
        if (sqK <= 0 || !expanding || holding) return 1
        var s = 1 - 0.05 * sqK * Math.max(0, Math.min(1, vh / 6))
        if (landed) s += 0.5 * sqK * (mh - 1)
        return Math.max(0.9, Math.min(1.06, s))
    }
    readonly property real neckNow: Theme.rLg * Math.max(0.4, 1 + (landed && expanding ? 3 * sqK * (mh - 1) : 0))
    // A spring past its target is soft-limited (8 %, as the island's).
    function soft(v) { return v > 1 ? 1 + Math.min((v - 1) * 0.6, 0.08) : Math.max(0, v) }
    function lerp(a, b, t) { return a + (b - a) * t }

    // The content comes in once the shape has nearly grown (fade, <= 160 ms) and leaves first (90 ms).
    readonly property bool contentWanted: wanted && held && !gate && mw > 0.72 && mh > 0.6 && !holding
    property real contentP: 0
    onContentWantedChanged: {
        contentAnim.stop()
        if (instant || Theme.quickMs <= 0) { contentP = contentWanted ? 1 : 0; return }
        contentAnim.to = contentWanted ? 1 : 0
        contentAnim.duration = contentWanted ? 160 : 90
        contentAnim.start()
    }
    NumberAnimation { id: contentAnim; target: sb; property: "contentP"; easing.type: Easing.OutCubic }

    // Test only (frontend/test-sidebars.sh): KURASHI_SIDEBAR_FREEZE names a file read at each open and close; "open 120"
    // holds the morph still 120 ms after it starts (for a shot), for 1.5 s, and logs it. Without the variable no file
    // is touched.
    readonly property string freezePath: Quickshell.env("KURASHI_SIDEBAR_FREEZE") || ""
    property int freezeMs: -1
    property int freezeHoldMs: 1500
    property bool frozen: false
    FileView { id: freezeFile; blockAllReads: true; printErrors: false }
    function readFreeze(phase) {
        freezeMs = -1
        if (freezePath === "") return
        // A new path each time: FileView reads it afresh (a reload of the same path kept the first text).
        freezeFile.path = ""
        freezeFile.path = freezePath
        freezeFile.reload()
        freezeFile.waitForJob()
        var t = String(freezeFile.text() || "").trim().split(/\s+/)
        if (t.length >= 2 && t[0] === phase) { freezeMs = Number(t[1]); freezeHoldMs = t.length >= 3 ? Number(t[2]) : 1500 }
        if (geometryLog) console.log("sidebar-freeze-read '" + t.join(" ") + "' " + phase + " " + freezeMs)
    }
    Timer {
        id: freezeTimer
        interval: Math.max(1, sb.freezeMs)
        onTriggered: {
            console.log("sidebar-frozen " + sb.side + " " + (sb.expanding ? "open" : "close") + " " + sb.freezeMs + " mw="
                + sb.mw.toFixed(3) + " mh=" + sb.mh.toFixed(3) + " content=" + sb.contentP.toFixed(2))
            // Held where they are (Behaviors off, the values written back), not paused: a resumed SpringAnimation
            // integrates the paused time at once.
            sb.frozen = true
            sb.freezeMs = -1
            var w = sb.mw, h = sb.mh
            sb.mw = w
            sb.mh = h
            contentAnim.stop()
            unfreezeTimer.start()
        }
    }
    Timer {
        id: unfreezeTimer
        interval: Math.max(1, sb.freezeHoldMs)
        onTriggered: {
            sb.frozen = false
            sb.driveTo(sb.wanted ? 1 : 0)
            contentAnim.to = sb.contentWanted ? 1 : 0
            contentAnim.start()
        }
    }

    // This output's config (an output's own entry wins); the sidebar keys are global.
    BarConfig { id: cfg; screen: sb.screen }
    // K71: each side's own keys (`sidebar.<side>.*`); `draw = auto` follows `layout.draw`, and only floating is drawn
    // apart from the panel today (dynamic and connected look as the panel did).
    readonly property string drawMode: {
        var d = cfg.valueOf("sidebar." + side + ".draw", "auto")
        return d === "auto" ? cfg.valueOf("layout.draw", "dynamic") : d
    }
    readonly property bool floating: drawMode === "floating"
    readonly property int wantW: {
        var w = Number(cfg.valueOf("sidebar." + side + ".width", 420))
        return isNaN(w) ? 420 : Math.max(320, Math.min(640, Math.round(w)))
    }
    // Never wider than the output less a gap.
    readonly property int colW: Math.min(wantW, screen ? screen.width - Theme.gap : wantW)
    readonly property var sections: {
        var v = cfg.valueOf("sidebar." + side + ".sections", side === "left" ? ["mod:ai:ai"]
            : ["header", "toggles", "sliders", "notifications", "calendar"])
        return Array.isArray(v) ? v.filter(function (s) { return typeof s === "string" && s !== "" }) : []
    }
    readonly property bool geometryLog: Quickshell.env("KURASHI_SIDEBAR_GEOMETRY") === "1"
    readonly property bool traceLog: Quickshell.env("KURASHI_SIDEBAR_TRACE") === "1"

    // The join, in the shape's canonical frame (a right sidebar, its bar edge at the top or on its own side; the frame is
    // mirrored for the left side, and vertically for a bottom bar and for the right sidebar beside a side bar, whose
    // button sits at that bar's bottom end).
    readonly property string barEdge: cfg.enabled ? cfg.edge : "none"
    readonly property bool joinTop: barEdge === "top" || barEdge === "bottom"
    readonly property bool joinSide: barEdge === side
    readonly property bool flipY: barEdge === "bottom" || (cfg.vertical && side === "right")
    // The bar draws a strip (flat and line chrome, and every side bar); floating groups stand on the desk (Bar.qml).
    readonly property bool barStrip: !(Theme.groups && Theme.lifted && !cfg.vertical)
    // The column joined to the bar takes the bar's own colour (one sheet); a free column the panel's.
    readonly property color fillColor: joinTop || joinSide ? Theme.surfaceAlpha : Theme.panel
    // Where the morph starts: the sidebar button's place at the bar's end (Bar.qml: the bar's padding and its group's
    // inset; a side bar's button heads or ends its column), as thick as the bar. Without a bar: the screen's corner.
    readonly property real barEnd: Theme.pad + (Theme.groups ? Theme.gap + 2 + Theme.xs : 0)
    // W36: on a top or bottom bar the column grows out of its sidebar button's own box (IslandGeom's registry, row 364;
    // SidebarButton registers `sidebar:<side>`), as an island card grows out of the pill: read when the column comes out
    // (and again on its first frame), latched while it is out. Kept as its distance from the column's own screen edge (the
    // window is anchored to it) and its width, 3 px in like the Stage's origins (the button's drawn square). No button
    // on this output (hidden, or a side bar): the bar's end, as before.
    property var origin: null
    function readOrigin() {
        var out = screen ? screen.name : ""
        var r = joinTop && out !== "" ? IslandGeom.rectOf(out, "sidebar:" + side) : null
        if (r === null || !screen) { origin = null; return }
        var near = side === "right" ? screen.width - (r.x + r.w) : r.x
        origin = { near: Math.max(0, near + 3), w: Math.max(8, r.w - 6) }
    }
    readonly property real nubW: joinSide ? 0 : (origin ? origin.w : Theme.barH)

    LazyLoader {
        active: sb.held
        PanelWindow {
            id: win
            screen: sb.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "kurashi-sidebar"
            WlrLayershell.keyboardFocus: sb.wanted ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            // While open the whole area takes clicks (the catcher, I152); folding back, none.
            mask: Region { item: inputArea }
            BackgroundEffect.blurRegion: Region { item: shapeRect }

            readonly property string outName: sb.screen ? sb.screen.name : ""
            // K59: this window's tile set, shared by its reliefs, and the pointer light's sensor. K61: the content stands
            // where it rests (cut to the shape), so the window's carry is none; the column's own relief carries its sheet.
            property var tileSheet: tilesLoader.item
            readonly property point sheetCarry: Qt.point(0, 0)
            Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
            LightSense {}

            // ---- geometry, canonical frame (see above): the box at the window's side, as tall as the window ----
            readonly property real boxW: Math.min(width, sb.colW + Math.ceil(sb.colW * 0.1) + Theme.rLg + Theme.gap + Theme.softR + 8)
            readonly property real boxH: height
            readonly property real inset: sb.floating ? Theme.gap : 0
            readonly property real sdy: sb.floating ? Theme.shadowDy : 0
            // The column at rest: flush with the outer edge (panel) or inset (floating; touching a side bar it joins).
            readonly property real rx1: boxW - (sb.floating && !sb.joinSide ? Theme.gap : 0)
            readonly property real rx0: rx1 - sb.colW
            readonly property real ry0: (sb.joinTop ? 0 : inset) + (sb.flipY && !sb.joinTop ? sdy : 0)
            readonly property real ry1: boxH - inset - (sb.flipY ? 0 : sdy)
            // The origin.
            readonly property real nX1: sb.joinTop ? Math.max(sb.nubW, boxW - (sb.origin ? sb.origin.near : sb.barEnd)) : rx1
            readonly property real nY0: sb.joinSide ? Theme.pad : ry0
            readonly property real nY1: sb.joinSide ? Theme.pad + Theme.barH : ry0
            // The shape now.
            readonly property real tw: Math.max(0, Math.min(1, sb.mw))
            readonly property real hp: sb.landed ? 1 : Math.max(0, Math.min(1, sb.mh))
            readonly property real shX1: sb.holding ? rx1 : sb.lerp(nX1, rx1, tw)
            readonly property real shW: Math.max(0, sb.lerp(sb.nubW, sb.colW, sb.soft(sb.mw)) * sb.squash)
            readonly property real shX0: shX1 - shW
            readonly property real shY0: sb.lerp(nY0, ry0, hp)
            readonly property real shY1: sb.lerp(nY1, ry1, hp)
            // K61: the column's material comes with its leading edges (the inner side, the free end), in output axes.
            readonly property point shapeCarry: Qt.point((sb.side === "left" ? -1 : 1) * (shX0 - rx0),
                (sb.flipY ? -1 : 1) * (shY1 - ry1))
            // Canonical → window.
            function realX(x0c, x1c) { return sb.side === "left" ? boxW - x1c : width - boxW + x0c }
            function realY(y0c, y1c) { return sb.flipY ? boxH - y1c : y0c }
            readonly property rect restRect: Qt.rect(realX(rx0, rx1), realY(ry0, ry1), sb.colW, ry1 - ry0)

            function logGeom() {
                if (!sb.geometryLog) return
                console.log("sidebar-geom " + outName + " " + sb.side + " " + (sb.floating ? "floating" : "panel")
                    + " win " + win.width + " " + win.height + " frame " + Math.round(restRect.x) + "," + Math.round(restRect.y)
                    + "," + Math.round(restRect.width) + "," + Math.round(restRect.height) + " bar " + (cfg.enabled ? cfg.edge : "none")
                    + " " + Theme.barH + " gap " + Theme.gap + " sections " + sb.sections.join(","))
            }
            onRestRectChanged: logGeom()
            Component.onCompleted: { if (sb.geometryLog) console.log("sidebar-window up " + sb.side); logGeom() }
            Component.onDestruction: {
                SidebarGeom.clear(outName)
                if (sb.geometryLog) console.log("sidebar-window down " + sb.side)
            }
            // At rest under a ruled bar, the span of the bar's edge the column (and its fillets) covers, for the bar to
            // leave its rule out there (SidebarGeom); withdrawn as soon as it moves.
            readonly property bool atRest: sb.wanted && !sb.gate && !sb.frozen && sb.mw === 1 && sb.mh === 1
                && !springW.running && !springH.running
            readonly property var opening: {
                if (!atRest || !shape.ruled || !(sb.joinTop || sb.joinSide)) return null
                if (sb.joinTop) {
                    var a = rx0 - shape.fL, b = rx1 + shape.fR
                    return sb.side === "left" ? [boxW - b, boxW - a] : [width - boxW + a, width - boxW + b]
                }
                var c = ry0 - shape.fT, d = ry1 + shape.fB
                return sb.flipY ? [boxH - d, boxH - c] : [c, d]
            }
            onOpeningChanged: {
                if (opening) SidebarGeom.set(outName, sb.barEdge, Math.round(opening[0]), Math.round(opening[1]))
                else SidebarGeom.clear(outName)
                if (sb.geometryLog) console.log("sidebar-opening " + sb.side + " " + (opening ? Math.round(opening[0]) + "," + Math.round(opening[1]) : "none"))
            }
            Connections {
                target: shapeRect.Window.window
                function onFrameSwapped() {
                    if (!sb.gate) return
                    sb.readOrigin()
                    sb.gate = false
                    if (sb.wanted) sb.driveTo(1)
                }
            }

            // The shape's body in window coordinates: the content's cut, the blur, and what counts as inside.
            Item {
                id: shapeRect
                x: win.realX(win.shX0, win.shX1)
                y: win.realY(win.shY0, win.shY1)
                width: win.shW
                height: Math.max(0, win.shY1 - win.shY0)
            }
            Item {
                id: inputArea
                width: sb.wanted ? win.width : 0
                height: sb.wanted ? win.height : 0
            }
            // The catcher: a press outside the column closes it; one on the column goes on to its controls.
            MouseArea {
                anchors.fill: parent
                enabled: sb.wanted
                acceptedButtons: Qt.AllButtons
                onPressed: ev => {
                    if (ev.x >= shapeRect.x && ev.x < shapeRect.x + shapeRect.width && ev.y >= shapeRect.y
                        && ev.y < shapeRect.y + shapeRect.height) {
                        ev.accepted = false
                        return
                    }
                    if (sb.geometryLog) console.log("sidebar-outside " + sb.side + " " + Math.round(ev.x) + "," + Math.round(ev.y))
                    Store.act("sidebar.close")
                }
            }

            // The shape, its shadow and its relief mask, in the canonical frame.
            Item {
                id: box
                x: sb.side === "left" ? 0 : win.width - win.boxW
                width: win.boxW
                height: win.boxH
                transform: Scale {
                    xScale: sb.side === "left" ? -1 : 1
                    yScale: sb.flipY ? -1 : 1
                    origin.x: win.boxW / 2
                    origin.y: win.boxH / 2
                }
                SoftShadow {
                    visible: sb.floating && shape.shown
                    x: shape.bodyRect.x
                    y: shape.bodyRect.y
                    width: shape.bodyRect.width
                    height: shape.bodyRect.height
                    radius: Theme.rLg
                    direction: sb.flipY ? -1 : 1
                    // The column is drawn mirrored for the left side (the Scale above): mirror the shadow's x back so it
                    // falls the way the light says on both sides (K67, row 421).
                    mirror: sb.side === "left" ? -1 : 1
                }
                ColumnShape {
                    id: shape
                    anchors.fill: parent
                    x0: win.shX0
                    x1: win.shX1
                    y0: win.shY0
                    y1: win.shY1
                    joinTop: sb.joinTop
                    joinSide: sb.joinSide
                    neck: sb.neckNow
                    squareOuter: !sb.floating
                    flipX: sb.side === "left"
                    ruled: sb.barStrip && Theme.outlineW > 0
                    chrome: sb.floating
                    flipY: sb.flipY
                    fill: sb.fillColor
                }
                // The shape's fill as a mask for its relief (I168): drawn only into `shapeMask`'s texture, which is redrawn
                // when the path changes (while the shape morphs) and never at rest.
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
                // Parked outside the window, as TileSheet's copies: a texture provider needs its paint node.
                ShaderEffectSource {
                    id: shapeMask
                    x: -100000
                    width: parent.width
                    height: parent.height
                    sourceItem: reliefBox.on ? maskShape : null
                    hideSource: true
                    live: false
                }
                Connections {
                    target: reliefBox.on ? shape : null
                    function onFillPathChanged() { shapeMask.scheduleUpdate() }
                }
            }
            // K59, K61: the column's material, clipped to the shape's fill (fillets included), under the content (over it
            // with `texture.text`); carried with the shape's leading edges, 0 at rest (the continuous sheet).
            Item {
                id: reliefBox
                readonly property bool on: Theme.texShell && shape.shown
                readonly property point carry: win.shapeCarry
                z: Theme.texText ? 2 : 0
                visible: on
                x: box.x
                width: win.boxW
                height: win.boxH
                transform: Scale {
                    xScale: sb.side === "left" ? -1 : 1
                    yScale: sb.flipY ? -1 : 1
                    origin.x: win.boxW / 2
                    origin.y: win.boxH / 2
                }
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

            // The content where the column rests, shown only inside the shape (cut while it grows or folds) and faded in
            // late. The column's one keyboard focus holder: Esc backs out of a page first, then closes.
            Item {
                id: reveal
                z: 1
                x: shapeRect.x
                y: shapeRect.y
                width: shapeRect.width
                height: shapeRect.height
                clip: true
                FocusScope {
                    id: content
                    x: win.restRect.x - reveal.x + Theme.pad
                    y: win.restRect.y - reveal.y + Theme.pad
                    width: win.restRect.width - 2 * Theme.pad
                    height: win.restRect.height - 2 * Theme.pad
                    opacity: sb.contentP
                    focus: true
                    Keys.onPressed: event => {
                        if (event.key !== Qt.Key_Escape) return
                        if (!(col.item && col.item.back && col.item.back())) Store.act("sidebar.close")
                        event.accepted = true
                    }
                    Component.onCompleted: Qt.callLater(function () { content.forceActiveFocus() })
                    Accessible.role: Accessible.Pane
                    Accessible.name: I18n.tr(sb.side === "left" ? "sidebar.a11y.left" : "sidebar.a11y.right")

                    Loader {
                        id: col
                        anchors.fill: parent
                        focus: true
                        sourceComponent: sb.side === "left" ? leftC : rightC
                    }
                }
            }
        }
    }
    Component {
        id: rightC
        RightColumn { sections: sb.sections; outName: sb.screen ? sb.screen.name : "" }
    }
    Component {
        id: leftC
        LeftColumn { tabs: sb.sections }
    }
}
