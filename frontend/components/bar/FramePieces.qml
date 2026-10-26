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
        model: fp.fillets
        Fillet {
            required property var modelData
            r: fp.r
            x: modelData.x; y: modelData.y; turn: modelData.turn
        }
    }
    // The rule: rectangles and arcs in the outline colour, or the pen's line.
    Repeater {
        model: fp.ow > 0 && !Theme.penOutline ? fp.rules : []
        Rectangle {
            required property var modelData
            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
            color: Theme.outlineColor
        }
    }
    Repeater {
        model: fp.ow > 0 && !Theme.penOutline ? fp.arcs : []
        Shape {
            required property var modelData
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.outlineColor
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
        active: fp.ow > 0 && Theme.penOutline && (fp.rules.length > 0 || fp.arcs.length > 0)
        sourceComponent: PenOutline {
            anchors.fill: parent
            color: Theme.outlineColor
            lineWidth: fp.ow
            seed: fp.seed
            paths: {
                var l = [], ox = fp.ox, oy = fp.oy, h = fp.ow / 2
                fp.rules.forEach(function (g) {
                    var a = g.w >= g.h
                        ? [{ x: g.x - ox, y: g.y + h - oy }, { x: g.x + g.w - ox, y: g.y + h - oy }]
                        : [{ x: g.x + h - ox, y: g.y - oy }, { x: g.x + h - ox, y: g.y + g.h - oy }]
                    l.push({ points: a, closed: false })
                })
                fp.arcs.forEach(function (a) {
                    l.push({ points: a.map(function (p) { return { x: p.x - ox, y: p.y - oy } }), closed: false })
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
