import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"

// The screen frame (K71, docs/ux/frame.md): a band round one output in the bar's own material, so the bar, the band and
// what stands on them read as one sheet with the screen's contents in a window cut into it. Drawn only while
// `runtime.layout` says `frame.on` for this output; no surface at all while it is off (Ma).
//
// Geometry comes from the layout (ShellLayout), never re-derived: `frame.band.<edge>` (0 where a docked bar is the band),
// `frame.radius` (the inner corners), `edges.<e>.holder` / `.reserve` (who keeps the edge's exclusive zone). The one
// thing read beside it is the docked bar's thickness, `Theme.barH` — what Bar.qml draws, so the fillets hang exactly
// under its ends (`edges.<e>.size` is the config value and can differ from the token for a frame or two after a change).
//
// Four static strips (ScreenCorners' pattern: plain items and Shapes, drawn once, 0 frames idle), click-through, no
// keyboard, layer Top, namespace `kurashi-frame`. The window cut into the sheet has its edges at `off(e)` = band + docked
// bar; the strips split the sheet so no pixel is drawn twice (the fill is translucent: an overlap would show as a darker
// seam):
// - top and bottom span the width, `off + radius` deep (with a docked bar that is the bar's thickness + the radius — the
//   part over the bar stays transparent: the fillets hang under the bar's ends, image 2). They draw their band, the
//   side bands down to the end of the fillets, and the inner fillets;
// - left and right are their band wide and run between the fillets' ends.
// The strip whose edge's holder is `frame` keeps the edge's zone (`exclusiveZone = edges.<e>.reserve`); the others
// ignore zones.
//
// Measured in the sway sandbox (probe, W43-frame): a surface that keeps a zone is placed inside the zones of those that
// were mapped before it, and its margin on the anchored edge is added to its zone. So: holders have margin 0 on their
// own edge, and top and bottom are made first (one Scope, declared first), the sides after them — a side strip that
// keeps its zone starts below the top strip's zone and its top margin is counted from there. niri (smithay's layer
// map) arranges the same way by mapping order; not verified there (the nested niri draws no layer surface, I207).
//
// The material (K59): each strip shares one TileSheet; the relief's sheet is registered in output coordinates, so the
// grain runs on from the bar into the band. Light.originOf counts every other window's zone on a non-Ignore window,
// which is wrong for the frame's own crossing strips (the top strip is not inside the side strips' zones): each strip
// names its true origin (`sheetOrigin`) and carries the difference (`sheetCarry`, honoured under the carried sheet,
// the default) until Light reads `sheetOrigin` itself (CONTRACT-CHANGE row 490).
//
// Chrome: line chrome rules the band's inner edge in the outline; with a docked bar the bar rules its own edge and
// ends where the fillet begins (Bar.qml), the frame's rule turns round the fillet and runs on down the side. With a pen
// (K62) the frame's rule is drawn by the pen. Flat, keycap and soft: a plain sheet.
Scope {
    id: fr
    required property var modelData
    readonly property string out: modelData ? modelData.name : ""

    // One subscription per output, held while the shell runs: it decides whether the frame exists at all.
    Watch { doc: "runtime.layout" }
    readonly property var live: ShellLayout.of(out)
    readonly property bool on: (live.frame || {}).on === true
    // What the strips draw: the layout while the frame is on, kept while it fades out (the zones go at once: `holds`).
    // A copy: Store merges patches into the document in place, so a kept reference would change under the fade.
    property var lay: ({})
    readonly property string liveKey: JSON.stringify(live)
    function copy(l) { return JSON.parse(JSON.stringify(l)) }
    // (Read from `live` itself: `on` may not have been re-evaluated yet when this runs.)
    onLiveKeyChanged: if ((live.frame || {}).on === true) lay = JSON.parse(liveKey)
    readonly property var fdoc: lay.frame || ({})
    readonly property int r: Math.max(0, Math.round(fdoc.radius || 0))
    // Rounded screen corners (K47 (6)): ScreenCorners' black fillets sit on the panel's outer corners, but the strips
    // are made later and would lie over them, so each strip draws the same black over its own part (black on black
    // where both are).
    BarConfig { id: cfg; screen: fr.modelData }
    readonly property int cr: {
        var v = cfg.valueOf("theme.shape.screen_corners", 0)
        return typeof v === "number" && v > 0 ? Math.round(v) : 0
    }

    function edgeOf(e) { return (lay.edges && lay.edges[e]) || ShellLayout.edgeOf(out, e) }
    function band(e) { var f = lay.frame; return f && f.on && f.band ? (f.band[e] || 0) : 0 }
    // A bar stands flush on edge `e` and is the band there.
    function docked(e) {
        var ed = edgeOf(e)
        return fdoc.on === true && ed.bar === true && ed.draw !== "floating" && ed.visibility !== "hidden" && band(e) === 0
    }
    readonly property var bands: ({ top: band("top"), bottom: band("bottom"), left: band("left"), right: band("right") })
    // The cut's edges, from each screen edge.
    readonly property var off: ({
        top: bands.top + (docked("top") ? Theme.barH : 0),
        bottom: bands.bottom + (docked("bottom") ? Theme.barH : 0),
        left: bands.left + (docked("left") ? Theme.barH : 0),
        right: bands.right + (docked("right") ? Theme.barH : 0)
    })
    function holds(e) { var ed = ShellLayout.edgeOf(out, e); return on && ed.holder === "frame" && (ed.reserve || 0) > 0 }
    function reserveOf(e) { return holds(e) ? Math.round(ShellLayout.edgeOf(out, e).reserve) : 0 }

    // Turning the frame on or off shows the band once over `motion.std` (cut when motion is off): the strips stay made
    // for the fade out and go with it.
    property bool held: false
    onOnChanged: if (on) { lay = copy(live); leave.stop(); held = true } else if (held) leave.restart()
    Component.onCompleted: { if (on) lay = copy(live); held = on }
    Timer { id: leave; interval: Math.max(1, Theme.stdMs); onTriggered: fr.held = false }

    // The rule's width: the outline under line chrome (boxed: an outline and no shadow; keycap and soft draw a plain sheet,
    // their ring and shadow belong to blocks); the pen draws it under a pen.
    readonly property int ow: Theme.boxed ? Theme.outlineW : 0

    // Points along a quarter circle (centre, radius, from angle a0 to a1, radians; screen axes, y down).
    function arc(cx, cy, rad, a0, a1) {
        var n = Math.max(6, Math.ceil(rad / 2)), pts = []
        for (var i = 0; i <= n; i++) {
            var a = a0 + (a1 - a0) * i / n
            pts.push({ x: cx + rad * Math.cos(a), y: cy + rad * Math.sin(a) })
        }
        return pts
    }

    // One strip. Its pieces are given in output coordinates; `ox`/`oy` is where the strip really stands on the output
    // (see the header), so `sheet` lays the output's plane under the window.
    component Strip: PanelWindow {
        id: strip
        // The frame's Scope (an inline component does not see the file's ids).
        required property var host
        property string edge: "top"
        property real ox: 0
        property real oy: 0
        // [{x, y, w, h}] (at most three), the fillets [{x, y, turn}], the rule's straight pieces [{x, y, w, h}] and its
        // arcs [[{x, y}, …]] — all in output coordinates.
        property var fills: []
        property var fillets: []
        property var rules: []
        property var arcs: []
        readonly property bool holder: host.holds(edge)

        screen: host.modelData
        color: "transparent"
        mask: Region {}
        exclusionMode: holder ? ExclusionMode.Normal : ExclusionMode.Ignore
        exclusiveZone: holder ? host.reserveOf(edge) : 0
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "kurashi-frame"

        // K59: one tile set for every relief of this strip.
        property var tileSheet: tilesLoader.item
        Loader { id: tilesLoader; active: Theme.texShell && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
        // The sheet's registration (see the header): the true origin, and the carry that corrects Light.originOf.
        readonly property point sheetOrigin: Qt.point(ox, oy)
        readonly property point lightOrigin: Light.originOf(strip)
        readonly property point sheetCarry: Qt.point(lightOrigin.x - ox, lightOrigin.y - oy)

        // The zone it keeps, for the origins of windows the compositor places inside it (Light.originOf).
        readonly property var zoneKey: [host.out, edge, holder ? host.reserveOf(edge) : 0].join("|")
        onZoneKeyChanged: Light.setZone(strip, host.out, edge, holder ? host.reserveOf(edge) : 0)
        Component.onCompleted: Light.setZone(strip, host.out, edge, holder ? host.reserveOf(edge) : 0)
        // Test only (KURASHI_FRAME_LOG=1, frontend/test-frame.sh): where the strip stands and what it draws.
        readonly property string geoLog: Quickshell.env("KURASHI_FRAME_LOG") === "1"
            ? ["FRAMEGEO", edge, ox, oy, width, height, holder, JSON.stringify(fills), JSON.stringify(rules)].join(" ") : ""
        onGeoLogChanged: if (geoLog !== "") console.log(geoLog)
        Component.onDestruction: Light.setZone(strip, "", edge, 0)

        BackgroundEffect.blurRegion: Region {
            item: fillRep.count > 0 ? fillRep.itemAt(0) : null
            Region { item: fillRep.count > 1 ? fillRep.itemAt(1) : null }
            Region { item: fillRep.count > 2 ? fillRep.itemAt(2) : null }
        }

        Item {
            id: sheet
            x: -strip.ox
            y: -strip.oy
            width: host.modelData ? host.modelData.width : 0
            height: host.modelData ? host.modelData.height : 0
            opacity: 0
            Component.onCompleted: opacity = Qt.binding(function () { return host.on ? 1 : 0 })
            Behavior on opacity {
                enabled: Theme.stdMs > 0
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }

            // The screen's outer corners (see `cr`), over the band.
            Repeater {
                model: strip.host.cr > 0 ? [[0, 0, 0], [sheet.width - strip.host.cr, 0, 90],
                    [sheet.width - strip.host.cr, sheet.height - strip.host.cr, 180], [0, sheet.height - strip.host.cr, 270]] : []
                z: 1
                Item {
                    required property var modelData
                    x: modelData[0]; y: modelData[1]; rotation: modelData[2]
                    width: strip.host.cr; height: strip.host.cr
                    z: 1
                    Quarter { fill: "black"; r: strip.host.cr }
                }
            }
            Repeater {
                id: fillRep
                model: strip.fills
                Rectangle {
                    required property var modelData
                    x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                    color: Theme.surfaceAlpha
                    Loader {
                        anchors.fill: parent
                        active: Theme.texShell
                        sourceComponent: Relief { anchors.fill: parent }
                    }
                }
            }
            Repeater {
                model: strip.fillets
                Fillet {
                    required property var modelData
                    host: strip.host
                    x: modelData.x; y: modelData.y; turn: modelData.turn
                }
            }
            // The rule: rectangles and arcs in the outline colour, or the pen's line.
            Repeater {
                model: host.ow > 0 && !Theme.penOutline ? strip.rules : []
                Rectangle {
                    required property var modelData
                    x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                    color: Theme.outlineColor
                }
            }
            Repeater {
                model: host.ow > 0 && !Theme.penOutline ? strip.arcs : []
                Shape {
                    required property var modelData
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Theme.outlineColor
                        strokeWidth: host.ow
                        capStyle: ShapePath.FlatCap
                        PathPolyline { path: modelData.map(function (p) { return Qt.point(p.x, p.y) }) }
                    }
                }
            }
        }
        // K62: the pen draws the rule (one Canvas the strip's size, painted once per change); in window coordinates.
        Loader {
            anchors.fill: parent
            active: host.ow > 0 && Theme.penOutline && (strip.rules.length > 0 || strip.arcs.length > 0)
            sourceComponent: PenOutline {
                anchors.fill: parent
                opacity: sheet.opacity
                color: Theme.outlineColor
                lineWidth: host.ow
                seed: ({ top: 0xF2A1, bottom: 0xF2A2, left: 0xF2A3, right: 0xF2A4 })[strip.edge]
                paths: {
                    var l = [], ox = strip.ox, oy = strip.oy, h = host.ow / 2
                    strip.rules.forEach(function (g) {
                        var a = g.w >= g.h
                            ? [{ x: g.x - ox, y: g.y + h - oy }, { x: g.x + g.w - ox, y: g.y + h - oy }]
                            : [{ x: g.x + h - ox, y: g.y - oy }, { x: g.x + h - ox, y: g.y + g.h - oy }]
                        l.push({ points: a, closed: false })
                    })
                    strip.arcs.forEach(function (a) {
                        l.push({ points: a.map(function (p) { return { x: p.x - ox, y: p.y - oy } }), closed: false })
                    })
                    return l
                }
            }
        }
    }

    // The fillet's shape: a quarter of an r × r square outside the arc.
    component Quarter: Shape {
        property color fill: "white"
        property real r: 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: fill
            strokeWidth: -1
            startX: 0; startY: 0
            PathLine { x: r; y: 0 }
            PathArc { x: 0; y: r; radiusX: r; radiusY: r; direction: PathArc.Counterclockwise }
            PathLine { x: 0; y: 0 }
        }
    }

    // A concave inner corner: the band's colour from the corner to the arc (ScreenCorners' fillet), turned per corner;
    // the material over it, cut to the same shape (a white copy as the relief's mask, drawn once).
    component Fillet: Item {
        id: fil
        required property var host
        property int turn: 0
        width: host.r
        height: host.r
        rotation: turn
        Quarter { fill: Theme.surfaceAlpha; r: fil.host.r }
        Loader {
            anchors.fill: parent
            active: Theme.texShell && host.r > 0
            sourceComponent: Item {
                Quarter { id: white; r: fil.host.r }
                ShaderEffectSource {
                    id: src
                    x: -100000
                    width: host.r
                    height: host.r
                    sourceItem: white
                    hideSource: true
                    live: false
                    Component.onCompleted: scheduleUpdate()
                }
                Relief { anchors.fill: parent; mask: src }
            }
        }
    }

    LazyLoader {
        active: fr.held
        Scope {
            id: strips
            readonly property real sw: fr.modelData ? fr.modelData.width : 0
            readonly property real sh: fr.modelData ? fr.modelData.height : 0
            readonly property var o: fr.off
            readonly property var b: fr.bands
            readonly property int r: fr.r
            readonly property int ow: fr.ow
            // Where a side strip starts and ends: below the fillets, and never above the zones the compositor already
            // placed it inside (a holder is placed within the top and bottom strips' zones; see the header).
            function sideFrom(e) { return fr.holds(e) && fr.holds("top") ? fr.reserveOf("top") : 0 }
            function sideTo(e) { return fr.holds(e) && fr.holds("bottom") ? fr.reserveOf("bottom") : 0 }
            readonly property real sideTop: o.top + r
            readonly property real sideBottom: o.bottom + r

            // The top or bottom strip's pieces (`top` true for the top one), in output coordinates.
            function across(top) {
                var W = sw, H = sh
                var e = top ? "top" : "bottom"
                // How far from this edge each side band is this strip's: to the fillets' end, or on to where the side
                // strip starts when this edge's zone is deeper than that (a floating bar's reserve).
                var reachL = Math.max(o[e] + r, top ? sideFrom("left") : sideTo("left"))
                var reachR = Math.max(o[e] + r, top ? sideFrom("right") : sideTo("right"))
                var d = Math.max(o[e] + r, b.left > 0 ? reachL : 0, b.right > 0 ? reachR : 0), y0 = top ? 0 : H - d
                var bw = b[e], dl = o.left - b.left, dr = o.right - b.right
                var fills = [], fillets = [], rules = [], arcs = []
                if (bw > 0) fills.push({ x: dl, y: top ? 0 : H - bw, w: W - dl - dr, h: bw })
                // The side bands from the cut's edge to their reach.
                var cols = [[b.left, reachL, 0], [b.right, reachR, W - b.right]]
                for (var i = 0; i < 2; i++) {
                    var cw = cols[i][0], reach = cols[i][1], cx = cols[i][2]
                    if (cw <= 0 || reach <= o[e]) continue
                    fills.push({ x: cx, y: top ? o[e] : H - reach, w: cw, h: reach - o[e] })
                    // Past the fillet the side's rule runs on in this strip.
                    var past = reach - o[e] - r
                    if (ow > 0 && past > 0)
                        rules.push({ x: i === 0 ? cw - ow : cx, y: top ? o[e] + r : H - reach, w: ow, h: past })
                }
                var edgeY = top ? o.top : H - o.bottom
                if (r > 0) {
                    fillets.push(top ? { x: o.left, y: o.top, turn: 0 } : { x: o.left, y: H - o.bottom - r, turn: 270 })
                    fillets.push(top ? { x: W - o.right - r, y: o.top, turn: 90 } : { x: W - o.right - r, y: H - o.bottom - r, turn: 180 })
                }
                if (ow > 0) {
                    // The straight rule along this band's inner edge (a docked bar rules its own edge).
                    if (bw > 0) {
                        var x0 = o.left + r - (r === 0 ? ow : 0), x1 = W - o.right - r + (r === 0 ? ow : 0)
                        rules.push({ x: x0, y: top ? edgeY - ow : edgeY, w: x1 - x0, h: ow })
                    } else if (r === 0) {
                        // A docked bar and square corners: the corner's pixel joins the bar's rule to the side's.
                        rules.push({ x: o.left - ow, y: top ? edgeY - ow : edgeY, w: ow, h: ow })
                        rules.push({ x: W - o.right, y: top ? edgeY - ow : edgeY, w: ow, h: ow })
                    }
                    // Round each fillet: centred on the arc's centre, the line inside the band.
                    if (r > 0) {
                        var rho = r + ow / 2, cyA = top ? o.top + r : H - o.bottom - r
                        var lx = o.left + r, rx = W - o.right - r
                        arcs.push(top ? fr.arc(lx, cyA, rho, -Math.PI / 2, -Math.PI) : fr.arc(lx, cyA, rho, Math.PI, Math.PI / 2))
                        arcs.push(top ? fr.arc(rx, cyA, rho, -Math.PI / 2, 0) : fr.arc(rx, cyA, rho, 0, Math.PI / 2))
                    }
                }
                return { y0: y0, d: d, fills: fills, fillets: fillets, rules: rules, arcs: arcs }
            }
            readonly property var topP: across(true)
            readonly property var bottomP: across(false)
            // A side strip's pieces (`left` true for the left one).
            function side(left) {
                var W = sw, H = sh
                var e = left ? "left" : "right", bw = b[e]
                var y0 = Math.max(sideTop, sideFrom(e)), y1 = H - Math.max(sideBottom, sideTo(e))
                var x = left ? 0 : W - Math.max(1, bw)
                var fills = [], rules = []
                if (bw > 0 && y1 > y0) {
                    fills.push({ x: left ? 0 : W - bw, y: y0, w: bw, h: y1 - y0 })
                    if (ow > 0) rules.push({ x: left ? bw - ow : W - bw, y: y0, w: ow, h: y1 - y0 })
                }
                return { x: x, y0: y0, y1: y1, w: Math.max(1, bw), fills: fills, rules: rules }
            }
            readonly property var leftP: side(true)
            readonly property var rightP: side(false)

            // Made in this order on purpose (see the header): top and bottom first, then the sides.
            // Once the top and bottom surfaces exist: a nested loader would otherwise finish, and map, before them.
            readonly property bool acrossMade: topStrip.backingWindowVisible && bottomStrip.backingWindowVisible
            Strip {
                id: topStrip
                host: fr
                edge: "top"
                anchors { top: true; left: true; right: true }
                implicitHeight: Math.max(1, strips.topP.d)
                ox: 0; oy: 0
                fills: strips.topP.fills; fillets: strips.topP.fillets; rules: strips.topP.rules; arcs: strips.topP.arcs
            }
            Strip {
                id: bottomStrip
                host: fr
                edge: "bottom"
                anchors { bottom: true; left: true; right: true }
                implicitHeight: Math.max(1, strips.bottomP.d)
                ox: 0; oy: strips.sh - Math.max(1, strips.bottomP.d)
                fills: strips.bottomP.fills; fillets: strips.bottomP.fillets; rules: strips.bottomP.rules; arcs: strips.bottomP.arcs
            }
            LazyLoader {
                active: strips.acrossMade && (strips.b.left > 0 || fr.holds("left"))
                Strip {
                    host: fr
                    edge: "left"
                    anchors { left: true; top: true; bottom: true }
                    implicitWidth: strips.leftP.w
                    margins.top: strips.leftP.y0 - strips.sideFrom("left")
                    margins.bottom: strips.sh - strips.leftP.y1 - strips.sideTo("left")
                    ox: 0; oy: strips.leftP.y0
                    fills: strips.leftP.fills; rules: strips.leftP.rules
                }
            }
            LazyLoader {
                active: strips.acrossMade && (strips.b.right > 0 || fr.holds("right"))
                Strip {
                    host: fr
                    edge: "right"
                    anchors { right: true; top: true; bottom: true }
                    implicitWidth: strips.rightP.w
                    margins.top: strips.rightP.y0 - strips.sideFrom("right")
                    margins.bottom: strips.sh - strips.rightP.y1 - strips.sideTo("right")
                    ox: strips.rightP.x; oy: strips.rightP.y0
                    fills: strips.rightP.fills; rules: strips.rightP.rules
                }
            }
        }
    }
}
