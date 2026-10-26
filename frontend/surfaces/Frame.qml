import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/island"
import "../components/bar"
import "../components/bar/framegeom.js" as FG

// The screen frame (K71, docs/ux/frame.md): a band round one output in the bar's own material, so the bar, the band and
// what stands on them read as one sheet with the screen's contents in a window cut into it. Drawn only while
// `runtime.layout` says `frame.on` for this output; no surface at all while it is off (Ma).
//
// Geometry comes from the layout (ShellLayout), never re-derived: `frame.band.<edge>` (0 where a docked bar is the band),
// `frame.radius` (the inner corners), `edges.<e>.holder` / `.reserve` (who keeps the edge's exclusive zone). The one
// thing read beside it is the docked bar's thickness, `Theme.barH` — what Bar.qml draws, so the fillets hang exactly
// under its ends (`edges.<e>.size` is the config value and can differ from the token for a frame or two after a change).
//
// Up to four static strips (ScreenCorners' pattern: plain items and Shapes, drawn once, 0 frames idle), click-through, no
// keyboard, layer Top, namespace `kurashi-frame`. The window cut into the sheet has its edges at `off(e)` = band + docked
// bar; the strips split the sheet so no pixel is drawn twice (the fill is translucent: an overlap would show as a darker
// seam): top and bottom span the width, `off + radius` deep — they draw their band, the side bands down to the end of the
// fillets, and the inner fillets; left and right are their band wide and run between the fillets' ends (the pieces:
// components/bar/framegeom.js, drawn by FramePieces).
//
// Row 492 (b): a docked bar's window carries its edge's strip — the band is the bar there and the fillets hang under its
// own ends — so no strip is made on an edge whose band is 0 under a docked bar (FG.docked); that bar keeps the frame's zone
// on its edge. One window and one tile sheet less per output in the default framed layout.
//
// The strip whose edge's holder is `frame` keeps the edge's zone (`exclusiveZone = edges.<e>.reserve`); the others ignore
// zones (ExclusionMode.Ignore, `exclusiveZone` never written: row 525). Measured in the sway sandbox (probe, W43-frame): a surface that keeps a zone is placed inside the zones of those
// that were mapped before it, and its margin on the anchored edge is added to its zone. So: holders have margin 0 on their
// own edge, and top and bottom (strips, or the bars carrying them) are mapped first, the sides after them — a side strip
// that keeps its zone starts below the top holder's zone and its top margin is counted from there. niri (smithay's layer
// map) arranges the same way by mapping order.
//
// The material (K59): each strip shares one TileSheet; the relief's sheet is registered in output coordinates, so the
// grain runs on from the bar into the band: each strip names its true origin (`sheetOrigin`), which Light.originOf reads
// (row 490) — counting every other window's zone would put the crossing strips `band` px off.
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
    // Rounded screen corners (K47 (6)): drawn by each strip over its own part (FramePieces).
    BarConfig { id: cfg; screen: fr.modelData }
    readonly property int cr: {
        var v = cfg.valueOf("theme.shape.screen_corners", 0)
        return typeof v === "number" && v > 0 ? Math.round(v) : 0
    }

    // The zones the strips keep, per edge (0: none). Through a string so it notifies only when a zone changes: every
    // document patch re-reads the layout, and rebuilt piece lists would remake the strips' items (a frame for nothing).
    readonly property string zonesKey: on ? JSON.stringify(FG.zones(live)) : JSON.stringify({ top: 0, bottom: 0, left: 0, right: 0 })
    readonly property var zones: JSON.parse(zonesKey)
    function holds(e) { return zones[e] > 0 }
    function reserveOf(e) { return zones[e] || 0 }
    // The edges whose strip a docked bar carries (row 492 b). Through a string, as the zones.
    readonly property string carriedKey: JSON.stringify({ top: FG.docked(lay, "top"), bottom: FG.docked(lay, "bottom"),
                                                          left: FG.docked(lay, "left"), right: FG.docked(lay, "right") })
    readonly property var carried: JSON.parse(carriedKey)
    // A carrying bar's window is on screen (its zone is placed before the side strips'), or nothing waits for it.
    function barMapped(e) { var b = IslandGeom.barOf(out, e); return !!b && b.mapped === true }
    // shell.qml: the side bars are mapped after the frame's top and bottom holders (or with no frame at once).
    property bool acrossMade: false
    readonly property bool acrossSettled: !held || acrossMade

    // Turning the frame on or off shows the band once over `motion.std` (cut when motion is off): the strips stay made
    // for the fade out and go with it.
    property bool held: false
    onOnChanged: if (on) { lay = copy(live); leave.stop(); held = true } else if (held) leave.restart()
    Component.onCompleted: { if (on) lay = copy(live); held = on }
    Timer { id: leave; interval: Math.max(1, Theme.stdMs); onTriggered: fr.held = false }

    // The rule's width: the outline under line chrome (boxed: an outline and no shadow; keycap and soft draw a plain sheet,
    // their ring and shadow belong to blocks); the pen draws it under a pen.
    readonly property int ow: Theme.boxed ? Theme.outlineW : 0

    // One strip. Its pieces are given in output coordinates; `ox`/`oy` is where the strip really stands on the output
    // (see the header), so its pieces lay the output's plane under the window.
    component Strip: PanelWindow {
        id: strip
        // The frame's Scope (an inline component does not see the file's ids).
        required property var host
        property string edge: "top"
        property real ox: 0
        property real oy: 0
        property var fills: []
        property var fillets: []
        property var rules: []
        property var arcs: []
        readonly property bool holder: host.holds(edge)

        screen: host.modelData
        color: "transparent"
        mask: Region {}
        exclusionMode: holder ? ExclusionMode.Normal : ExclusionMode.Ignore
        // Row 525: written only while it holds the zone. Writing `exclusiveZone` at all (even 0) turns a PanelWindow to
        // ExclusionMode.Normal, and a non-holder was then placed inside the other holders' zones (measured: under a 32 px
        // top bar with reserve off the side strips came out 976 px tall, 32 px below their fillets; 1008 with this).
        Binding on exclusiveZone { when: strip.holder; value: strip.host.reserveOf(strip.edge); restoreMode: Binding.RestoreNone }
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "kurashi-frame"

        // K59: one tile set for every relief of this strip.
        property var tileSheet: tilesLoader.item
        Loader { id: tilesLoader; active: Theme.texShell && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
        // The sheet's registration (row 490): the true origin (see the header).
        readonly property point sheetOrigin: Qt.point(ox, oy)

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
            item: pieces.fillAt(0)
            Region { item: pieces.fillCount > 1 ? pieces.fillAt(1) : null }
            Region { item: pieces.fillCount > 2 ? pieces.fillAt(2) : null }
        }

        FramePieces {
            id: pieces
            ox: strip.ox
            oy: strip.oy
            winW: strip.width
            winH: strip.height
            sw: host.modelData ? host.modelData.width : 0
            sh: host.modelData ? host.modelData.height : 0
            r: host.r
            ow: host.ow
            cr: host.cr
            seed: ({ top: 0xF2A1, bottom: 0xF2A2, left: 0xF2A3, right: 0xF2A4 })[strip.edge]
            fills: strip.fills
            fillets: strip.fillets
            rules: strip.rules
            arcs: strip.arcs
            opacity: 0
            Component.onCompleted: opacity = Qt.binding(function () { return strip.host.on ? 1 : 0 })
            Behavior on opacity {
                enabled: Theme.stdMs > 0
                NumberAnimation { duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
            }
        }
    }

    LazyLoader {
        active: fr.held
        Scope {
            id: strips
            readonly property real sw: fr.modelData ? fr.modelData.width : 0
            readonly property real sh: fr.modelData ? fr.modelData.height : 0
            readonly property var g: FG.geometry(fr.lay, Theme.barH, sw, sh, fr.ow, fr.zones)
            readonly property var topP: FG.across(g, true)
            readonly property var bottomP: FG.across(g, false)
            readonly property var leftP: FG.side(g, true)
            readonly property var rightP: FG.side(g, false)
            function sideFrom(e) { return FG.sideFrom(g, e) }
            function sideTo(e) { return FG.sideTo(g, e) }

            // Made in this order on purpose (see the header): top and bottom first, then the sides — once the top and
            // bottom surfaces (or the bars that carry them) exist: a nested loader would otherwise finish, and map, first.
            readonly property bool acrossMade: (fr.carried.top ? fr.barMapped("top") : (topL.item !== null && topL.item.backingWindowVisible))
                && (fr.carried.bottom ? fr.barMapped("bottom") : (bottomL.item !== null && bottomL.item.backingWindowVisible))
            Binding { target: fr; property: "acrossMade"; value: strips.acrossMade }
            Component.onDestruction: fr.acrossMade = false
            LazyLoader {
                id: topL
                active: !fr.carried.top
                Strip {
                    host: fr
                    edge: "top"
                    anchors { top: true; left: true; right: true }
                    implicitHeight: Math.max(1, strips.topP.d)
                    ox: 0; oy: 0
                    fills: strips.topP.fills; fillets: strips.topP.fillets; rules: strips.topP.rules; arcs: strips.topP.arcs
                }
            }
            LazyLoader {
                id: bottomL
                active: !fr.carried.bottom
                Strip {
                    host: fr
                    edge: "bottom"
                    anchors { bottom: true; left: true; right: true }
                    implicitHeight: Math.max(1, strips.bottomP.d)
                    ox: 0; oy: strips.sh - Math.max(1, strips.bottomP.d)
                    fills: strips.bottomP.fills; fillets: strips.bottomP.fillets; rules: strips.bottomP.rules; arcs: strips.bottomP.arcs
                }
            }
            LazyLoader {
                active: strips.acrossMade && !fr.carried.left && (strips.g.b.left > 0 || fr.holds("left"))
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
                active: strips.acrossMade && !fr.carried.right && (strips.g.b.right > 0 || fr.holds("right"))
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
