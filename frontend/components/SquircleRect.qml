import QtQuick
import QtQuick.Shapes
import "../core"
import "../core/corner.js" as Corner

// A rectangle with squircle corners (`theme.shape.corners = squircle`, I281) where a Rectangle drew a rounded one: its
// fill and its border as an inner band (odd-even, as a Rectangle's border lies inside its edge). A corner of half the
// shorter side or more is a pill's end and stays round. Only made while the look is a squircle one (Block's Loaders).
Shape {
    id: sr
    property real radius: 0
    property color color: "transparent"
    property real borderWidth: 0
    property color borderColor: "transparent"
    preferredRendererType: Shape.CurveRenderer

    readonly property real half: Math.min(width, height) / 2
    readonly property string outer: width < 1 || height < 1 ? ""
        : Corner.rect(0, 0, width, height, radius, radius, radius, radius, radius < half - 0.5 ? Theme.squircle : 0)
    readonly property real bw: Math.max(0, borderWidth)
    readonly property real ir: Math.max(0, radius - bw)
    readonly property string inner: bw <= 0 || width <= 2 * bw || height <= 2 * bw ? ""
        : Corner.rect(bw, bw, width - 2 * bw, height - 2 * bw, ir, ir, ir, ir, ir < half - bw - 0.5 ? Theme.squircle : 0)

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: sr.color
        PathSvg { path: sr.color.a > 0 ? (sr.inner !== "" ? sr.inner : sr.outer) : "" }
    }
    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillColor: sr.borderColor
        fillRule: ShapePath.OddEvenFill
        PathSvg { path: sr.inner !== "" && sr.borderColor.a > 0 ? sr.outer + " " + sr.inner : "" }
    }
}
