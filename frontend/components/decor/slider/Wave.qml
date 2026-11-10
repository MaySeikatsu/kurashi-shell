import QtQuick
import QtQuick.Shapes
import "../../../core"

// Wave (session 28): the level's part is a wave, the rest a thin straight rail, the handle a bar between them. The wave
// stands still at rest and runs only while the slider is held (rule 5): its phase is the one animation, gated on
// `pressed`.
SliderBase {
    id: sl
    property bool hovered: false
    readonly property real v: Math.max(0, Math.min(1, value))
    readonly property real len: vertical ? height : width
    readonly property real thick: vertical ? width : height
    readonly property real at: Math.round((len - 4) * v)
    property real phase: 0
    readonly property real amp: sl.pressed ? 3.2 : (sl.hovered ? 2.6 : 2)
    NumberAnimation on phase {
        running: sl.pressed && Theme.springOn && sl.visible
        from: 0; to: 2 * Math.PI; duration: 900; loops: Animation.Infinite
    }
    function wave() {
        var w = Math.max(0, sl.at - 5), y0 = sl.thick / 2, s = "M 1.5 " + y0.toFixed(2), n = Math.max(2, Math.round(w / 3))
        if (w < 4) return ""
        for (var i = 1; i <= n; i++) {
            var x = 1.5 + (w - 1.5) * i / n
            // (the wave calms toward both ends, so it meets the cap and the handle level)
            var k = Math.min(1, Math.min(x - 1.5, w - x) / 8)
            s += " L " + x.toFixed(2) + " " + (y0 + Math.sin(x / 3.4 - sl.phase) * sl.amp * k).toFixed(2)
        }
        return s
    }
    Item {
        id: body
        width: sl.len; height: sl.thick
        anchors.centerIn: parent
        rotation: sl.vertical ? -90 : 0
        Rectangle {
            x: sl.at + 9; y: Math.round((body.height - 3) / 2)
            width: Math.max(0, body.width - x); height: 3; radius: 1.5
            color: Theme.selected
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.accent; strokeWidth: 3; fillColor: "transparent"
                capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathSvg { path: sl.wave() }
            }
        }
        Rectangle {
            x: sl.at + (4 - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            width: sl.pressed ? 6 : 4; height: Math.min(body.height, 18); radius: width / 2
            color: Theme.accent
            Behavior on width { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs } }
        }
    }
}
