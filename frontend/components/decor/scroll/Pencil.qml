import QtQuick
import QtQuick.Shapes
import "../../../core"

// Pencil (W53.7, docs/ux/styles.md §9 kami, K60): a scroll bar drawn in pencil on the page — the track a faint graphite
// line that wavers a little (a hand, not a ruler), the thumb a firm stroke over it, thick in its middle and thinning to
// both ends as a pencil pressed and lifted; while held or under the pointer the stroke is darker. No arrows (a notebook
// has none). Roles only (rule 4): graphite is the text's ink thinned. Static: it redraws only when the view moves.
ScrollBase {
    id: sb
    readonly property bool vert: orientation === Qt.Vertical
    readonly property real len: vert ? height : width
    readonly property real thick: vert ? width : height
    readonly property real thumbLen: Math.max(18, len * Math.min(1, size))
    readonly property real thumbAt: Math.max(0, Math.min(len - thumbLen, len * position))
    readonly property real mid: thick / 2

    // The track: one long, faint, slightly bowed line.
    Shape {
        anchors.fill: parent
        visible: sb.size < 1
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.alpha(Theme.fg, 0.28)
            strokeWidth: 1
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: sb.vert ? sb.mid : 2; startY: sb.vert ? 2 : sb.mid
            PathCubic {
                x: sb.vert ? sb.mid + 0.6 : sb.len - 2; y: sb.vert ? sb.len - 2 : sb.mid + 0.6
                control1X: sb.vert ? sb.mid + 1.2 : sb.len * 0.3; control1Y: sb.vert ? sb.len * 0.3 : sb.mid + 1.2
                control2X: sb.vert ? sb.mid - 1.0 : sb.len * 0.7; control2Y: sb.vert ? sb.len * 0.7 : sb.mid - 1.0
            }
        }
    }
    // The thumb: a tapered stroke (a closed outline: two gentle curves meeting in points).
    Shape {
        visible: sb.size < 1
        x: sb.vert ? 0 : sb.thumbAt
        y: sb.vert ? sb.thumbAt : 0
        width: sb.vert ? sb.thick : sb.thumbLen
        height: sb.vert ? sb.thumbLen : sb.thick
        preferredRendererType: Shape.CurveRenderer
        readonly property real w: 3.6
        ShapePath {
            strokeColor: "transparent"
            fillColor: Qt.alpha(Theme.fg, sb.pressed || sb.hovered ? 0.85 : 0.62)
            startX: sb.vert ? sb.mid : 1; startY: sb.vert ? 1 : sb.mid
            PathCubic {
                x: sb.vert ? sb.mid : sb.thumbLen - 1; y: sb.vert ? sb.thumbLen - 1 : sb.mid
                control1X: sb.vert ? sb.mid + 2.6 : sb.thumbLen * 0.25; control1Y: sb.vert ? sb.thumbLen * 0.25 : sb.mid + 2.6
                control2X: sb.vert ? sb.mid + 2.2 : sb.thumbLen * 0.75; control2Y: sb.vert ? sb.thumbLen * 0.75 : sb.mid + 2.2
            }
            PathCubic {
                x: sb.vert ? sb.mid : 1; y: sb.vert ? 1 : sb.mid
                control1X: sb.vert ? sb.mid - 2.0 : sb.thumbLen * 0.75; control1Y: sb.vert ? sb.thumbLen * 0.75 : sb.mid - 2.0
                control2X: sb.vert ? sb.mid - 2.4 : sb.thumbLen * 0.25; control2Y: sb.vert ? sb.thumbLen * 0.25 : sb.mid - 2.4
            }
        }
    }
}
