import QtQuick
import QtQuick.Shapes
import "../../core"

// Bullet (W53.6): the marks the `[decor]` keys `menu.mark`, `title.mark`, `start.mark` and `scroll.cap` name, drawn in
// `ink` on a `size` px tall box — `square` (NieR:Automata's list bullet: a solid square), `diamond`, `heart` (a 7 × 6 pixel
// heart on whole pixels: the pastel desktop's), `fleur` (an original filigree spearhead with two scrolls, twice as wide as
// tall, pointing right; `mirror` points it left: the pointer pair either side of a selected row, after Hollow Knight's
// idea, never its art). Static: one paint per size and colour. Any part may use it.
Item {
    id: b
    property string kind: "square"
    property color ink: Theme.fg
    property real size: 6
    property bool mirror: false
    readonly property real px: Math.max(1, Math.round(size / 6))
    implicitWidth: kind === "fleur" ? size * 2 : kind === "heart" ? px * 7 : size
    implicitHeight: kind === "heart" ? px * 6 : size
    width: implicitWidth
    height: implicitHeight
    visible: kind !== "none" && kind !== ""

    Rectangle {
        visible: b.kind === "square"
        anchors.fill: parent
        color: b.ink
        antialiasing: false
    }
    Rectangle {
        visible: b.kind === "diamond"
        anchors.centerIn: parent
        width: b.size / Math.SQRT2
        height: width
        rotation: 45
        color: b.ink
    }
    // The heart on whole pixels: rows of (start, length) in a 7-wide grid.
    Repeater {
        model: b.kind === "heart" ? [[1, 2], [4, 2], [0, 7], [0, 7], [1, 5], [2, 3], [3, 1]] : []
        Rectangle {
            required property var modelData
            required property int index
            readonly property int r: index < 2 ? 0 : index - 1
            x: modelData[0] * b.px
            y: r * b.px
            width: modelData[1] * b.px
            height: b.px
            color: b.ink
            antialiasing: false
        }
    }
    // The fleur: a slim spearhead toward +x, a stem behind it and two scrolls curling back from its foot.
    Shape {
        id: fl
        visible: b.kind === "fleur"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { origin.x: b.width / 2; xScale: b.mirror ? -1 : 1 }
        readonly property real w: b.width
        readonly property real h: b.height
        readonly property real m: h / 2
        ShapePath {
            strokeColor: "transparent"
            fillColor: b.ink
            startX: fl.w; startY: fl.m
            PathLine { x: fl.w * 0.62; y: fl.m - fl.h * 0.22 }
            PathLine { x: fl.w * 0.5; y: fl.m }
            PathLine { x: fl.w * 0.62; y: fl.m + fl.h * 0.22 }
            PathLine { x: fl.w; y: fl.m }
        }
        ShapePath {
            strokeColor: b.ink
            strokeWidth: Math.max(1, b.size / 9)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: 0; startY: fl.m
            PathLine { x: fl.w * 0.52; y: fl.m }
            // The upper scroll: up and back from the spear's foot into a small curl.
            PathMove { x: fl.w * 0.5; y: fl.m }
            PathCubic {
                x: fl.w * 0.16; y: fl.h * 0.1
                control1X: fl.w * 0.42; control1Y: fl.m - fl.h * 0.45
                control2X: fl.w * 0.26; control2Y: fl.h * 0.0
            }
            PathCubic {
                x: fl.w * 0.2; y: fl.h * 0.34
                control1X: fl.w * 0.06; control1Y: fl.h * 0.2
                control2X: fl.w * 0.1; control2Y: fl.h * 0.36
            }
            // The lower scroll, mirrored.
            PathMove { x: fl.w * 0.5; y: fl.m }
            PathCubic {
                x: fl.w * 0.16; y: fl.h * 0.9
                control1X: fl.w * 0.42; control1Y: fl.m + fl.h * 0.45
                control2X: fl.w * 0.26; control2Y: fl.h * 1.0
            }
            PathCubic {
                x: fl.w * 0.2; y: fl.h * 0.66
                control1X: fl.w * 0.06; control1Y: fl.h * 0.8
                control2X: fl.w * 0.1; control2Y: fl.h * 0.64
            }
        }
    }
}
