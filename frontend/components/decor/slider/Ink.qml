import QtQuick
import QtQuick.Shapes
import "../../../core"

// Ink (session 28): the level is one stroke of a loaded brush — full where it sets down, thinning as it runs —, the
// rest the faint line the dry brush leaves, and the knob a seal's red dot pressed where the stroke ends. For the looks
// of paper and ink. Static: the paths change only with the level.
SliderBase {
    id: sl
    property bool hovered: false
    readonly property real v: Math.max(0, Math.min(1, value))
    readonly property real len: vertical ? height : width
    readonly property real thick: vertical ? width : height
    readonly property real dot: Math.min(14, thick)
    readonly property real at: (len - dot) * v + dot / 2
    function stroke() {
        var w = sl.at, m = sl.thick / 2
        if (w < 3) return ""
        // Upper edge out, lower edge back: 4 px thick at the start, a hair at the end, with the brush's small waver.
        var up = "M 0 " + (m - 1).toFixed(2), n = Math.max(3, Math.round(w / 12)), i, x, t
        for (i = 1; i <= n; i++) {
            x = w * i / n; t = i / n
            up += " L " + x.toFixed(2) + " " + (m - 2.6 * (1 - 0.72 * t) - 0.5 * Math.sin(i * 1.9)).toFixed(2)
        }
        for (i = n; i >= 0; i--) {
            x = w * i / n; t = i / n
            up += " L " + x.toFixed(2) + " " + (m + 2.4 * (1 - 0.78 * t) + 0.45 * Math.sin(i * 2.3 + 1)).toFixed(2)
        }
        return up + " Z"
    }
    function blot(r) {
        var s = "", n = 10
        for (var i = 0; i <= n; i++) {
            var a = 2 * Math.PI * i / n, k = r * (1 + 0.09 * Math.sin(i * 2.7) + 0.06 * Math.cos(i * 4.1))
            s += (i === 0 ? "M " : " L ") + (k * Math.cos(a)).toFixed(2) + " " + (k * Math.sin(a)).toFixed(2)
        }
        return s + " Z"
    }
    Item {
        id: body
        width: sl.len; height: sl.thick
        anchors.centerIn: parent
        rotation: sl.vertical ? -90 : 0
        // The dry brush: short pieces of a thin line.
        Row {
            x: sl.at; y: Math.round((body.height - 1.5) / 2)
            spacing: 3
            Repeater {
                model: Math.max(0, Math.floor((body.width - sl.at) / 10))
                Rectangle { required property int index; width: 7 - (index % 3); height: 1.5; radius: 0.75; color: Theme.dim; opacity: 0.55 }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath { strokeWidth: -1; fillColor: Theme.fg; PathSvg { path: sl.stroke() } }
        }
        Shape {
            x: sl.at; y: body.height / 2
            scale: sl.pressed ? 1.18 : (sl.hovered ? 1.08 : 1)
            preferredRendererType: Shape.CurveRenderer
            Behavior on scale { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutBack } }
            ShapePath { strokeWidth: -1; fillColor: Theme.accent; PathSvg { path: sl.blot(sl.dot / 2) } }
        }
    }
}
