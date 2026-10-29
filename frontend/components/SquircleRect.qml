import QtQuick
import QtQuick.Shapes
import "../core"
import "../core/corner.js" as Corner

// A rectangle with squircle corners (`theme.shape.corners = squircle`, I281) where a Rectangle drew a rounded one: its
// fill and its border inside its edge (as a Rectangle's), stroked along the border's centre line. A corner of half the
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
    // The border as a stroke along its centre line (an odd-even band between two squircles is uneven: their curves are
    // not parallel, and the band thinned to a speck where a corner meets its side, W56).
    readonly property real mr: Math.max(0, radius - bw / 2)
    readonly property string mid: bw <= 0 || width <= bw || height <= bw ? ""
        : Corner.rect(bw / 2, bw / 2, width - bw, height - bw, mr, mr, mr, mr, mr < half - bw / 2 - 0.5 ? Theme.squircle : 0)
    ShapePath {
        strokeWidth: sr.bw > 0 ? sr.bw : -1
        strokeColor: sr.borderColor
        fillColor: "transparent"
        PathSvg { path: sr.mid !== "" && sr.borderColor.a > 0 ? sr.mid : "" }
    }
}
