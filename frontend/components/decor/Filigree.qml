import QtQuick
import QtQuick.Shapes
import "../../core"

// Filigree (W53.6): an ornament rule — `[decor] title.rule` / `bar.rule = filigree` and the lock faces that frame a field
// with one. An original design in the spirit of Hollow Knight's menu dividers, never its art: a diamond at the centre,
// a pair of scrolls curling out from it on each side, and a hairline tapering to nothing toward both ends. `ink` colours
// it; `width` is the whole rule, `height` the scrolls' reach. Static (one paint per size and colour).
Item {
    id: f
    property color ink: Theme.fg
    implicitHeight: 12
    readonly property real m: height / 2
    readonly property real c: width / 2
    readonly property real r: Math.min(height * 1.6, width * 0.12)
    readonly property real stroke: Math.max(1, height / 10)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // The tapering line: a long thin wedge each side, widest by the centre.
        ShapePath {
            strokeColor: "transparent"
            fillColor: f.ink
            startX: 0; startY: f.m
            PathLine { x: f.c - f.r * 0.9; y: f.m - f.stroke * 0.8 }
            PathLine { x: f.c + f.r * 0.9; y: f.m - f.stroke * 0.8 }
            PathLine { x: f.width; y: f.m }
            PathLine { x: f.c + f.r * 0.9; y: f.m + f.stroke * 0.8 }
            PathLine { x: f.c - f.r * 0.9; y: f.m + f.stroke * 0.8 }
            PathLine { x: 0; y: f.m }
        }
        // The centre diamond.
        ShapePath {
            strokeColor: "transparent"
            fillColor: f.ink
            startX: f.c; startY: f.m - f.height * 0.48
            PathLine { x: f.c + f.height * 0.3; y: f.m }
            PathLine { x: f.c; y: f.m + f.height * 0.48 }
            PathLine { x: f.c - f.height * 0.3; y: f.m }
            PathLine { x: f.c; y: f.m - f.height * 0.48 }
        }
        // Scrolls: from the diamond's sides, up and out into a curl, and down and out into a curl, both sides.
        ShapePath {
            strokeColor: f.ink
            strokeWidth: f.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: f.c + f.height * 0.3; startY: f.m
            PathCubic {
                x: f.c + f.r; y: f.m - f.height * 0.2
                control1X: f.c + f.r * 0.45; control1Y: f.m - f.height * 0.05
                control2X: f.c + f.r * 0.6; control2Y: f.m - f.height * 0.5
            }
            PathCubic {
                x: f.c + f.r * 0.72; y: f.m - f.height * 0.18
                control1X: f.c + f.r * 1.12; control1Y: f.m + f.height * 0.02
                control2X: f.c + f.r * 0.8; control2Y: f.m + f.height * 0.02
            }
            PathMove { x: f.c + f.height * 0.3; y: f.m }
            PathCubic {
                x: f.c + f.r; y: f.m + f.height * 0.2
                control1X: f.c + f.r * 0.45; control1Y: f.m + f.height * 0.05
                control2X: f.c + f.r * 0.6; control2Y: f.m + f.height * 0.5
            }
            PathCubic {
                x: f.c + f.r * 0.72; y: f.m + f.height * 0.18
                control1X: f.c + f.r * 1.12; control1Y: f.m - f.height * 0.02
                control2X: f.c + f.r * 0.8; control2Y: f.m - f.height * 0.02
            }
            PathMove { x: f.c - f.height * 0.3; y: f.m }
            PathCubic {
                x: f.c - f.r; y: f.m - f.height * 0.2
                control1X: f.c - f.r * 0.45; control1Y: f.m - f.height * 0.05
                control2X: f.c - f.r * 0.6; control2Y: f.m - f.height * 0.5
            }
            PathCubic {
                x: f.c - f.r * 0.72; y: f.m - f.height * 0.18
                control1X: f.c - f.r * 1.12; control1Y: f.m + f.height * 0.02
                control2X: f.c - f.r * 0.8; control2Y: f.m + f.height * 0.02
            }
            PathMove { x: f.c - f.height * 0.3; y: f.m }
            PathCubic {
                x: f.c - f.r; y: f.m + f.height * 0.2
                control1X: f.c - f.r * 0.45; control1Y: f.m + f.height * 0.05
                control2X: f.c - f.r * 0.6; control2Y: f.m + f.height * 0.5
            }
            PathCubic {
                x: f.c - f.r * 0.72; y: f.m + f.height * 0.18
                control1X: f.c - f.r * 1.12; control1Y: f.m - f.height * 0.02
                control2X: f.c - f.r * 0.8; control2Y: f.m - f.height * 0.02
            }
        }
    }
}
