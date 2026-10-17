import QtQuick
import QtQuick.Shapes

// A sparkline of the last samples, oldest left, newest at the right edge (docs/ux/sysmon.md "History"). `capacity`
// is the number of samples the full width holds (60 in the panel, 30 in the bar), so a shorter history sits at the
// right edge rather than stretching. `ceiling` fixes the scale (100 for percentages); 0 fits the data. Screen readers
// get the owner's description of it, never the pixels.
Shape {
    id: spark
    required property var theme
    property var values: []
    property real ceiling: 100
    property int capacity: 60
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

    // The baseline: a faint rule along the bottom, so a short history still reads as a chart area.
    ShapePath {
        strokeColor: spark.theme.outline
        strokeWidth: 1
        fillColor: "transparent"
        PathPolyline {
            path: [Qt.point(0, spark.height - 0.5), Qt.point(spark.width, spark.height - 0.5)]
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
        var step = w / Math.max(1, spark.capacity - 1)
        var out = []
        for (var i = 0; i < n; i++) {
            var x = w - (n - 1 - i) * step
            var y = 1 + h - Math.min(1, Math.max(0, v[i] / top)) * h
            out.push(Qt.point(x, y))
        }
        return out
    }
}
