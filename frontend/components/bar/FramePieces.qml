import QtQuick
import QtQuick.Shapes
import "../../core"
import ".."

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
    function cdx(c) { return c.charAt(1) === "l" ? -liftLeft : liftRight }
    function cdy(c) { return c.charAt(0) === "t" ? -liftTop : liftBottom }
    function gx(g) { return g.c ? g.x + cdx(g.c) : g.band ? g.x - liftLeft : g.x }
    function gy(g) { return g.c ? g.y + cdy(g.c) : g.grow === "top" ? g.y - liftTop : g.y }
    function gw(g) { return g.band ? g.w + liftLeft + liftRight : g.w }
    function gh(g) { return g.grow === "top" ? g.h + liftTop : g.grow === "bottom" ? g.h + liftBottom : g.h }
    // A rule piece runs along x (a band's edge) unless it is marked `vert` (a side's rule, 0 long at rest).
    function isH(g) { return g.vert === true ? false : g.w >= g.h }
    readonly property var shownRules: cutRules(rules, openings)
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
        model: fp.cr > 0 ? [[0, 0, 0], [fp.sw - fp.cr, 0, 90], [fp.sw - fp.cr, fp.sh - fp.cr, 180], [0, fp.sh - fp.cr, 270]] : []
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
        model: fp.fills
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
        visible: fp.cover.h > 0 && fp.cover.w > 0
        color: Theme.surfaceAlpha
        Loader {
            anchors.fill: parent
            active: Theme.texShell && parent.visible
            sourceComponent: Relief { anchors.fill: parent }
        }
    }
    Repeater {
        model: fp.fillets
        Fillet {
            required property var modelData
            r: fp.r
            x: fp.gx(modelData); y: fp.gy(modelData); turn: modelData.turn
        }
    }
    // The rule: rectangles and arcs in the outline colour, or the pen's line.
    Repeater {
        model: fp.ow > 0 && !Theme.penOutline ? fp.shownRules : []
        Rectangle {
            required property var modelData
            x: fp.gx(modelData); y: fp.gy(modelData); width: fp.gw(modelData); height: fp.gh(modelData)
            color: Theme.outlineColor
        }
    }
    Rectangle {
        x: fp.coverRule.x; y: fp.coverRule.y; width: fp.coverRule.w; height: fp.coverRule.h
        visible: fp.ow > 0 && !Theme.penOutline && fp.coverRule.h > 0 && fp.coverRule.w > 0
        color: Theme.outlineColor
    }
    Repeater {
        model: fp.ow > 0 && !Theme.penOutline ? fp.arcs : []
        Shape {
            required property var modelData
            x: fp.cdx(modelData.c)
            y: fp.cdy(modelData.c)
            width: fp.width
            height: fp.height
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.outlineColor
                strokeWidth: fp.ow
                capStyle: ShapePath.FlatCap
                PathPolyline { path: modelData.p.map(function (p) { return Qt.point(p.x, p.y) }) }
            }
        }
    }
    // K62: the pen draws the rule (one Canvas the window's size, painted once per change).
    Loader {
        x: fp.ox
        y: fp.oy
        width: fp.winW
        height: fp.winH
        active: fp.ow > 0 && Theme.penOutline && (fp.shownRules.length > 0 || fp.arcs.length > 0)
        sourceComponent: PenOutline {
            anchors.fill: parent
            color: Theme.outlineColor
            lineWidth: fp.ow
            seed: fp.seed
            paths: {
                var l = [], ox = fp.ox, oy = fp.oy, h = fp.ow / 2
                var lifted = fp.shownRules.map(function (g) {
                    return { x: fp.gx(g), y: fp.gy(g), w: fp.gw(g), h: fp.gh(g), vert: g.vert }
                })
                if (fp.coverRule.h > 0 && fp.coverRule.w > 0) lifted.push(fp.coverRule)
                lifted.forEach(function (g) {
                    if (g.w <= 0 || g.h <= 0) return
                    var a = fp.isH(g)
                        ? [{ x: g.x - ox, y: g.y + h - oy }, { x: g.x + g.w - ox, y: g.y + h - oy }]
                        : [{ x: g.x + h - ox, y: g.y - oy }, { x: g.x + h - ox, y: g.y + g.h - oy }]
                    l.push({ points: a, closed: false })
                })
                fp.arcs.forEach(function (a) {
                    var dx = fp.cdx(a.c), dy = fp.cdy(a.c)
                    l.push({ points: a.p.map(function (p) { return { x: p.x + dx - ox, y: p.y + dy - oy } }), closed: false })
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
            startX: 0; startY: 0
            PathLine { x: r; y: 0 }
            PathArc { x: 0; y: r; radiusX: r; radiusY: r; direction: PathArc.Counterclockwise }
            PathLine { x: 0; y: 0 }
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
