import QtQuick
import QtQuick.Shapes
import "../../../core"

// Note (W53.7, docs/ux/styles.md §9 kami, K60): a tooltip — and a toast, drawn as the look's tooltip — as a note torn
// from the notebook: the page's paper, outlined by hand in the text's ink (four slightly bowed strokes that overshoot at
// the corners, as a quick pen box does), the red margin rule down its start (the content keeps clear of it: the callers'
// padding is wider than the rule's place) and a faint blue ruled line under the text's baseline. Roles only (rule 4).
// Static: drawn once per size.
TooltipBase {
    id: tt
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property string fill: Theme.decor("tooltip.fill", "")
    readonly property color ink: Qt.alpha(Theme.outlineColor, 0.9)
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: tt.fill !== "" ? tt.fill : Theme.surface
    }
    // The blue rule a little above the foot (where a line of writing sits), then the red margin rule.
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 3; rightMargin: 3; bottomMargin: Math.min(8, tt.height * 0.18) }
        height: tt.hair
        color: Qt.alpha(Theme.secondary, 0.35)
    }
    Rectangle {
        x: 5
        anchors { top: parent.top; bottom: parent.bottom; topMargin: 2; bottomMargin: 2 }
        width: tt.hair
        color: Qt.alpha(Theme.accent, 0.75)
    }
    // The hand-drawn box: each side a separate stroke, a pixel or two past the corners.
    Shape {
        id: box
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property real w: width
        readonly property real h: height
        ShapePath {
            strokeColor: tt.ink
            strokeWidth: 1.3
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: -1; startY: 1.2
            PathQuad { x: box.w + 1.5; y: 0.6; controlX: box.w * 0.5; controlY: -0.4 }
            PathMove { x: box.w - 0.6; y: -1 }
            PathQuad { x: box.w - 1.2; y: box.h + 1.2; controlX: box.w + 0.8; controlY: box.h * 0.5 }
            PathMove { x: box.w + 0.8; y: box.h - 0.8 }
            PathQuad { x: -1.2; y: box.h - 1.4; controlX: box.w * 0.5; controlY: box.h + 0.6 }
            PathMove { x: 0.8; y: box.h + 1 }
            PathQuad { x: 1.4; y: -0.8; controlX: -0.6; controlY: box.h * 0.5 }
        }
    }
}
