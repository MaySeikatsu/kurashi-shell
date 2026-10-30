import QtQuick
import QtQuick.Shapes

// CaptionGlyph (W53.2): a caption button's mark — close (×), minimize (_), maximize (□ with a heavy top), restore (two
// boxes) — drawn in `ink` on a `size` px square, strokes `stroke` px; with an `edge` colour each stroke is first drawn
// 1 px wider all round in it (7's white marks with a dark rim). Any caption part may use it (Gloss, Glass). Static.
Item {
    id: g
    property string kind: "close"
    property color ink: "#ffffff"
    property color edge: "transparent"
    property real size: 9
    property real stroke: 2
    readonly property bool rimmed: edge.a > 0
    width: size
    height: size

    // ×: two strokes corner to corner, flat caps; the rim under them.
    Shape {
        visible: g.kind === "close"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: g.rimmed ? g.edge : "transparent"
            strokeWidth: g.stroke + 2
            fillColor: "transparent"
            capStyle: ShapePath.SquareCap
            startX: 0.5; startY: 0.5
            PathLine { x: g.size - 0.5; y: g.size - 0.5 }
            PathMove { x: g.size - 0.5; y: 0.5 }
            PathLine { x: 0.5; y: g.size - 0.5 }
        }
        ShapePath {
            strokeColor: g.ink
            strokeWidth: g.stroke
            fillColor: "transparent"
            capStyle: ShapePath.SquareCap
            startX: 0.5; startY: 0.5
            PathLine { x: g.size - 0.5; y: g.size - 0.5 }
            PathMove { x: g.size - 0.5; y: 0.5 }
            PathLine { x: 0.5; y: g.size - 0.5 }
        }
    }
    // _: a bar along the bottom, half the square wide.
    Item {
        visible: g.kind === "minimize"
        anchors.fill: parent
        Rectangle {
            visible: g.rimmed
            x: -1; y: g.size - g.stroke - 1
            width: Math.round(g.size * 0.7) + 2; height: g.stroke + 2
            color: g.edge
        }
        Rectangle { x: 0; y: g.size - g.stroke; width: Math.round(g.size * 0.7); height: g.stroke; color: g.ink }
    }
    // □: a box with a top twice the stroke; restore: two smaller boxes, the back one up-right.
    component Box: Item {
        id: bx
        property real s: g.size
        width: s
        height: s
        Rectangle { visible: g.rimmed; x: -1; y: -1; width: bx.s + 2; height: bx.s + 2; color: "transparent"; border.width: 1; border.color: g.edge }
        Rectangle {
            visible: g.rimmed
            x: Math.max(1, g.stroke / 2) + 1; y: g.stroke * 1.5 + 1
            width: bx.s - 2 * Math.max(1, g.stroke / 2) - 2; height: bx.s - g.stroke * 1.5 - Math.max(1, g.stroke / 2) - 2
            color: "transparent"; border.width: 1; border.color: g.edge
        }
        Rectangle { width: bx.s; height: g.stroke * 1.5; color: g.ink }
        Rectangle { y: bx.s - Math.max(1, g.stroke / 2); width: bx.s; height: Math.max(1, g.stroke / 2); color: g.ink }
        Rectangle { width: Math.max(1, g.stroke / 2); height: bx.s; color: g.ink }
        Rectangle { x: bx.s - Math.max(1, g.stroke / 2); width: Math.max(1, g.stroke / 2); height: bx.s; color: g.ink }
    }
    Box { visible: g.kind === "maximize" }
    Item {
        visible: g.kind === "restore"
        anchors.fill: parent
        Box { x: Math.round(g.size * 0.3); y: 0; s: Math.round(g.size * 0.7) }
        Box { x: 0; y: Math.round(g.size * 0.3); s: Math.round(g.size * 0.7) }
    }
}
