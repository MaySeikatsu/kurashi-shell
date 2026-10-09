import QtQuick
import QtQuick.Shapes

// A sparkline of the last samples, oldest left, newest at the right edge (docs/ux/sysmon.md "History").
// `ceiling` fixes the scale (100 for percentages); 0 fits the data. Screen readers get the owner's
// description of it, never the pixels.
Shape {
    id: spark
    required property var theme
    property var values: []
    property real ceiling: 100
    property color stroke: spark.theme.dim
    property string description: ""

    implicitWidth: 120
    implicitHeight: 28
    preferredRendererType: Shape.CurveRenderer
    Accessible.role: Accessible.Graphic
    Accessible.name: description

    ShapePath {
        strokeColor: spark.stroke
        strokeWidth: 1.5
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathPolyline {
            path: spark.points()
        }
    }

    // Points of the line, one per sample; a single sample draws nothing (there is no line yet).
    function points() {
        var v = spark.values || []
        var n = v.length
        if (n < 2) return []
        var top = spark.ceiling > 0 ? spark.ceiling : Math.max(1, Math.max.apply(null, v))
        var w = spark.width
        var h = spark.height - 2
        var step = w / 59
        var out = []
        for (var i = 0; i < n; i++) {
            var x = w - (n - 1 - i) * step
            var y = 1 + h - Math.min(1, Math.max(0, v[i] / top)) * h
            out.push(Qt.point(x, y))
        }
        return out
    }
}
