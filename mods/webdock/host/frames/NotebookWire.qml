import QtQuick
import QtQuick.Shapes

// The notebook's coil (W69; docs/ux/webdock.md "Page styles" › Notebook): twin wire loops, a pair every `geom.pitch`
// px, each from its punched slot over the sheet's bound edge to the coil's axis on the dock's side. A metal tone from
// the theme: the wire in `outline`, lit toward `fg` along its top, with a contact shadow in `line` on the light's far
// side. Drawn once as three static paths (one Shape, SVG path strings rebuilt only when the card's size changes): no
// Canvas, no per-frame work (Ma). Lies over the top sheet, so the page turns under it.
Shape {
    id: wire

    property var theme: null
    property NotebookGeom geom: null

    preferredRendererType: Shape.CurveRenderer
    // The light's side (K82's light comes from the top left in the paper looks): the shadow falls the other way.
    readonly property point shadowOff: Qt.point(1.2, 1.5)
    readonly property color metal: theme ? Qt.tint(theme.outline, Qt.alpha(theme.fg, 0.18)) : "#9a8f80"
    readonly property color shine: theme ? Qt.alpha(theme.fg, 0.4) : "#99ffffff"
    readonly property color shade: theme ? Qt.alpha(theme.line, 0.5) : "#80000000"

    function loopsPath(dx, dy) {
        var g = geom
        if (!g) return ""
        var s = ""
        for (var i = 0; i < g.loops.length; i++) {
            var a = g.loops[i]
            var p = g.pt(a, g.holeD + 1.5), c = g.pt(a - 1.5, (g.holeD + g.axisD) / 2), e = g.pt(a - 4, g.axisD)
            s += "M " + (p.x + dx) + " " + (p.y + dy) + " Q " + (c.x + dx) + " " + (c.y + dy) + " " + (e.x + dx) + " " + (e.y + dy) + " "
        }
        return s
    }
    // (built here, not per path: the geometry's change is the one trigger)
    readonly property string shadowPath: loopsPath(shadowOff.x, shadowOff.y)
    readonly property string wirePath: loopsPath(0, 0)
    readonly property string shinePath: loopsPath(-0.6, -0.8)

    ShapePath {
        strokeColor: wire.shade
        strokeWidth: 3.6
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathSvg { path: wire.shadowPath }
    }
    ShapePath {
        strokeColor: wire.metal
        strokeWidth: 3.2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathSvg { path: wire.wirePath }
    }
    ShapePath {
        strokeColor: wire.shine
        strokeWidth: 1
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathSvg { path: wire.shinePath }
    }
}
