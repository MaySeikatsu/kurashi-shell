import QtQuick
import QtQuick.Shapes
import "../../core"
import ".."
import "../../core/corner.js" as Corner

// The drawn part of one frame strip (K71, docs/ux/frame.md): its band fills (in the bar's material, K59), the inner fillets,
// the rule (line chrome: rectangles and arcs, or the pen's line, K62) and the screen's rounded outer corners over it. Laid
// out in output coordinates: this item is the output's plane, placed at (−ox, −oy) in a window that stands at (ox, oy) on
// its output — a frame strip, or the docked bar that carries its edge's strip (row 492 b). Static Shapes: drawn once,
// 0 frames idle.
Item {
    id: fp
    // Where the window stands on its output, and its size (the pen's canvas is the window's, not the output's).
    property real ox: 0
    property real oy: 0
    property real winW: 0
    property real winH: 0
    property real sw: 0
    property real sh: 0
    // Inner corner radius, rule width (0: none), screen corner radius (0: none), the pen's salt.
    property int r: 0
    property int ow: 0
    property int cr: 0
    property int seed: 0
    // [{x, y, w, h}] (at most three), the fillets [{x, y, turn}], the rule's straight pieces [{x, y, w, h}] and its arcs
    // [[{x, y}, …]] — all in output coordinates.
    property var fills: []
    property var fillets: []
    property var rules: []
    property var arcs: []
    // Where a neighbour joined to the band covers its rule — a sidebar's end or outer side, the dock (SidebarGeom's
    // openings, [{edge, from, to}] along that edge in output px): the rule is left out there, so the neighbour's outline
    // runs round its fillet into the rule's ends (one sheet, as on a bar: row 521).
    property var openings: []
    // What this instance draws: the sheet (fills, fillets, the screen's corners) and/or the rule. A window that draws its
    // own body between them (a docked bar carrying its strip) takes two instances, the rule over its body: else the body's
    // last row hides the arcs' first half pixel and the rule steps where it meets the body's outline (I302).
    property bool drawSheet: true
    property bool drawRule: true
    // Docked bars that slide (hover, empty desktop: Bar.qml): the cut on edge `e` stands `lift<E>` px nearer the screen edge
    // than the pieces were laid out for (the bar's shown depth; IslandGeom.lifts). A piece hanging in a corner (`c`: a
    // fillet, its arc, a square corner's pixel) moves with both of its corner's edges; the band's straight rule (`band`)
    // reaches the moved corners; a piece marked `grow: <edge>` (the side bands in a top or bottom strip, and their rule)
    // keeps its far end and reaches the moved cut. `cover` ({x, y, w, h}, output px; 0: none) is the band between a sliding
    // bar's body and the frame's thickness while the body is slid nearer the edge than that, `coverRule` the band's inner
    // rule along it. Numbers, not new piece lists: the delegates stay made while a bar moves.
    property real liftTop: 0
    property real liftBottom: 0
    property real liftLeft: 0
    property real liftRight: 0
    property var cover: ({ x: 0, y: 0, w: 0, h: 0 })
    property var coverRule: ({ x: 0, y: 0, w: 0, h: 0 })
    // Where a column or the dock joined to the band under a slid-out bar covers the cover's rule (as `openings`).
    property var coverOpenings: []
    readonly property var coverRules: coverRule.w > 0 && coverRule.h > 0 ? cutRules([coverRule], coverOpenings) : []
    function cdx(c) { return c.charAt(1) === "l" ? -liftLeft : liftRight }
    function cdy(c) { return c.charAt(0) === "t" ? -liftTop : liftBottom }
    function gx(g) { return g.c ? g.x + cdx(g.c) : g.band ? g.x - liftLeft : g.x }
    function gy(g) { return g.c ? g.y + cdy(g.c) : g.grow === "top" ? g.y - liftTop : g.y }
    function gw(g) { return g.band ? g.w + liftLeft + liftRight : g.w }
    function gh(g) { return Math.max(0, g.grow === "top" ? g.h + liftTop : g.grow === "bottom" ? g.h + liftBottom : g.h) }
    // A rule piece runs along x (a band's edge) unless it is marked `vert` (a side's rule, 0 long at rest).
    function isH(g) { return g.vert === true ? false : g.w >= g.h }
    // The rule as drawn: moved with the lifts first, then cut where a neighbour covers it (a lifted piece can reach into an
    // opening it was clear of at rest). The delegates take these as they are.
    readonly property var shownRules: cutRules(rules.map(function (g) {
        return { x: gx(g), y: gy(g), w: gw(g), h: gh(g), vert: g.vert }
    }), openings)
    // An arc is left out where a neighbour joined to the band reaches into its corner (the neighbour's outline turns there).
    function covered(a) {
        var dx = cdx(a.c), dy = cdy(a.c), x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
        for (var i = 0; i < a.p.length; i++) {
            x0 = Math.min(x0, a.p[i].x + dx); x1 = Math.max(x1, a.p[i].x + dx)
            y0 = Math.min(y0, a.p[i].y + dy); y1 = Math.max(y1, a.p[i].y + dy)
        }
        for (var j = 0; j < openings.length; j++) {
            var o = openings[j], e = o.edge
            if (e === "top" && a.c.charAt(0) === "t" || e === "bottom" && a.c.charAt(0) === "b") {
                if (o.from < x1 && o.to > x0) return true
            } else if (e === "left" && a.c.charAt(1) === "l" || e === "right" && a.c.charAt(1) === "r") {
                if (o.from < y1 && o.to > y0) return true
            }
        }
        return false
    }
    readonly property var shownArcs: arcs.filter(function (a) { return !covered(a) })
    // Where a neighbour joined to the band stands (an opening), its fillet's outline turns into this rule's row: that part
    // of the turn is drawn here, over the band (I302) — the neighbour's window draws the rest and may be stacked under this
    // strip, and it stops at the band's line anyway. The same circle as the neighbour's (ColumnShape `ruled`: the layout's
    // one radius round the fillet's centre, the line from `r` to `r + ow` out), from the rule's row up to 45°.
    function nearEdge(e, mid) {
        return e === "top" ? mid < sh / 2 : e === "bottom" ? mid > sh / 2 : e === "left" ? mid < sw / 2 : mid > sw / 2
    }
    readonly property var tailArcs: {
        var out = []
        if (!drawRule || r <= 0 || ow <= 0 || openings.length === 0) return out
        var lifted = rules.map(function (g) { return { x: gx(g), y: gy(g), w: gw(g), h: gh(g), vert: g.vert } })
        for (var j = 0; j < openings.length; j++) {
            var o = openings[j], side = o.edge === "left" || o.edge === "right", L = NaN, r0 = 0, r1 = 0
            // (only where this strip rules that edge under the opening, and only at an end the rule runs on past: a
            // neighbour reaching the rule's end — a column from corner to corner — turns there without a fillet)
            for (var i = 0; i < lifted.length && isNaN(L); i++) {
                var g = lifted[i], horiz = isH(g)
                if (side === horiz || !nearEdge(o.edge, horiz ? g.y + g.h / 2 : g.x + g.w / 2)) continue
                var s0 = horiz ? g.x : g.y, s1 = horiz ? g.x + g.w : g.y + g.h
                if (o.to < s0 || o.from > s1) continue
                L = o.edge === "bottom" ? g.y : o.edge === "top" ? g.y + g.h : o.edge === "left" ? g.x + g.w : g.x
                r0 = s0; r1 = s1
            }
            if (isNaN(L)) continue
            var nx = o.edge === "left" ? 1 : o.edge === "right" ? -1 : 0, ny = o.edge === "top" ? 1 : o.edge === "bottom" ? -1 : 0
            var a = Math.min(r, (o.to - o.from) / 2), rho = a + ow / 2
            var ends = [[o.from, 1, o.from > r0 + 0.5], [o.to, -1, o.to < r1 - 0.5]]
            for (var k = 0; k < 2; k++) {
                if (!ends[k][2]) continue
                var at = ends[k][0], sg = ends[k][1], pts = []
                var cx = (side ? L : at) + nx * a, cy = (side ? at : L) + ny * a
                for (var q = 0; q <= 8; q++) {
                    var th = Math.PI / 4 * q / 8, c = Math.cos(th), sn = Math.sin(th) * sg
                    pts.push({ x: cx + rho * (-nx * c + (side ? 0 : sn)), y: cy + rho * (-ny * c + (side ? sn : 0)) })
                }
                out.push(pts)
            }
        }
        return out
    }
    function cutRules(list, ops) {
        if (!ops || ops.length === 0) return list
        var out = []
        for (var i = 0; i < list.length; i++) {
            var g = list[i], horiz = fp.isH(g)
            var segs = [[horiz ? g.x : g.y, horiz ? g.x + g.w : g.y + g.h]]
            var mid = horiz ? g.y + g.h / 2 : g.x + g.w / 2
            for (var j = 0; j < ops.length; j++) {
                var o = ops[j], side = o.edge === "left" || o.edge === "right"
                if (side === horiz) continue
                var near = o.edge === "top" ? mid < sh / 2 : o.edge === "bottom" ? mid > sh / 2
                    : o.edge === "left" ? mid < sw / 2 : mid > sw / 2
                if (!near) continue
                var n = []
                for (var k = 0; k < segs.length; k++) {
                    var s = segs[k]
                    if (o.to <= s[0] || o.from >= s[1]) { n.push(s); continue }
                    if (o.from > s[0]) n.push([s[0], o.from])
                    if (o.to < s[1]) n.push([o.to, s[1]])
                }
                segs = n
            }
            for (var m = 0; m < segs.length; m++) {
                var a = segs[m][0], b = segs[m][1]
                out.push(Object.assign({}, g, horiz ? { x: a, w: b - a } : { y: a, h: b - a }))
            }
        }
        return out
    }
    // The fill items (a window's blur region names them).
    function fillAt(i) { return i < fillRep.count ? fillRep.itemAt(i) : null }
    readonly property int fillCount: fillRep.count

    x: -ox
    y: -oy
    width: sw
    height: sh

    // The screen's outer corners (K47 (6)): ScreenCorners' black fillets sit on the panel's outer corners, but a strip is
    // made later and would lie over them, so it draws the same black over its own part (black on black where both are).
    Repeater {
        model: fp.drawSheet && fp.cr > 0 ? [[0, 0, 0], [fp.sw - fp.cr, 0, 90], [fp.sw - fp.cr, fp.sh - fp.cr, 180], [0, fp.sh - fp.cr, 270]] : []
        z: 1
        Item {
            required property var modelData
            x: modelData[0]; y: modelData[1]; rotation: modelData[2]
            width: fp.cr; height: fp.cr
            z: 1
            Quarter { fill: "black"; r: fp.cr }
        }
    }
    Repeater {
        id: fillRep
        model: fp.drawSheet ? fp.fills : []
        Rectangle {
            required property var modelData
            x: fp.gx(modelData); y: fp.gy(modelData); width: fp.gw(modelData); height: fp.gh(modelData)
            color: Theme.surfaceAlpha
            Loader {
                anchors.fill: parent
                active: Theme.texShell
                sourceComponent: Relief { anchors.fill: parent }
            }
        }
    }
    Rectangle {
        x: fp.cover.x; y: fp.cover.y; width: fp.cover.w; height: fp.cover.h
        visible: fp.drawSheet && fp.cover.h > 0 && fp.cover.w > 0
        color: Theme.surfaceAlpha
        Loader {
            anchors.fill: parent
            active: Theme.texShell && parent.visible
            sourceComponent: Relief { anchors.fill: parent }
        }
    }
    Repeater {
        model: fp.drawSheet ? fp.fillets : []
        Fillet {
            required property var modelData
            r: fp.r
            x: fp.gx(modelData); y: fp.gy(modelData); turn: modelData.turn
        }
    }
    // The rule: rectangles and arcs in the outline colour, or the pen's line.
    Repeater {
        model: fp.drawRule && fp.ow > 0 && !Theme.framePen ? fp.shownRules : []
        Rectangle {
            required property var modelData
            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
            color: Theme.frameOutlineColor
        }
    }
    Repeater {
        model: fp.drawRule && fp.ow > 0 && !Theme.framePen ? fp.coverRules : []
        Rectangle {
            required property var modelData
            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
            color: Theme.frameOutlineColor
        }
    }
    Repeater {
        model: fp.drawRule && fp.ow > 0 && !Theme.framePen ? fp.shownArcs : []
        Shape {
            required property var modelData
            x: fp.cdx(modelData.c)
            y: fp.cdy(modelData.c)
            width: fp.width
            height: fp.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.frameOutlineColor
                strokeWidth: fp.ow
                capStyle: ShapePath.FlatCap
                PathPolyline { path: modelData.p.map(function (p) { return Qt.point(p.x, p.y) }) }
            }
        }
    }
    Repeater {
        model: fp.ow > 0 && !Theme.framePen ? fp.tailArcs : []
        Shape {
            required property var modelData
            width: fp.width
            height: fp.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.frameOutlineColor
                strokeWidth: fp.ow
                capStyle: ShapePath.FlatCap
                PathPolyline { path: modelData.map(function (p) { return Qt.point(p.x, p.y) }) }
            }
        }
    }
    // K62: the pen draws the rule (one Canvas the window's size, painted once per change).
    Loader {
        x: fp.ox
        y: fp.oy
        width: fp.winW
        height: fp.winH
        active: fp.drawRule && fp.ow > 0 && Theme.framePen && (fp.shownRules.length > 0 || fp.arcs.length > 0 || fp.coverRules.length > 0)
        sourceComponent: PenOutline {
            anchors.fill: parent
            color: Theme.frameOutlineColor
            line: Theme.framePenLine
            lineWidth: fp.ow
            seed: fp.seed
            paths: {
                var l = [], ox = fp.ox, oy = fp.oy, h = fp.ow / 2
                var lifted = fp.shownRules.concat(fp.coverRules)
                lifted.forEach(function (g) {
                    if (g.w <= 0 || g.h <= 0) return
                    var a = fp.isH(g)
                        ? [{ x: g.x - ox, y: g.y + h - oy }, { x: g.x + g.w - ox, y: g.y + h - oy }]
                        : [{ x: g.x + h - ox, y: g.y - oy }, { x: g.x + h - ox, y: g.y + g.h - oy }]
                    l.push({ points: a, closed: false })
                })
                fp.shownArcs.forEach(function (a) {
                    var dx = fp.cdx(a.c), dy = fp.cdy(a.c)
                    l.push({ points: a.p.map(function (p) { return { x: p.x + dx - ox, y: p.y + dy - oy } }), closed: false })
                })
                fp.tailArcs.forEach(function (t) {
                    l.push({ points: t.map(function (p) { return { x: p.x - ox, y: p.y - oy } }), closed: false })
                })
                return l
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
            // (the squircle corner in a squircle look, I281: the band's inner corner as the shapes draw theirs)
            PathSvg { path: r > 0 ? "M 0 0 L " + r + " 0" + Corner.quarter(r, 0, r, 0, 0, r, Theme.squircle) + " Z" : "" }
        }
    }
    // A concave inner corner: the band's colour from the corner to the arc (ScreenCorners' fillet), turned per corner; the
    // material over it, cut to the same shape (a white copy as the relief's mask, drawn once).
    component Fillet: Item {
        id: fil
        property int turn: 0
        property int r: 0
        width: r
        height: r
        rotation: turn
        Quarter { fill: Theme.surfaceAlpha; r: fil.r }
        Loader {
            anchors.fill: parent
            active: Theme.texShell && fil.r > 0
            sourceComponent: Item {
                Quarter { id: white; r: fil.r }
                ShaderEffectSource {
                    id: src
                    x: -100000
                    width: fil.r
                    height: fil.r
                    sourceItem: white
                    hideSource: true
                    live: false
                    Component.onCompleted: scheduleUpdate()
                }
                Relief { anchors.fill: parent; mask: src }
            }
        }
    }
}
