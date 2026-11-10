import QtQuick
import "../core"

// The ground of a painted surface larger than one stroke (I471b; the user's mock-up of a desktop widget: a clock on one
// broad stroke, a calendar on three): bands of a brush, one under another, each starting and stopping at its own place
// and lapping over the next, so the surface is covered as a brush would cover it. A surface no taller than a stroke is
// one stroke. Fill the surface with it; it draws past the surface's sides. Static.
Item {
    id: pb
    property color color: Qt.alpha(Theme.accent, 0.5)
    readonly property int n: Math.max(1, Math.round(height / 74))
    readonly property real step: height / n
    function rnd(i: int, k: int): real {
        var v = Math.sin((i + 1) * 127.1 + k * 311.7 + Math.round(pb.width) * 0.37 + Math.round(pb.height) * 0.91) * 43758.5453
        return v - Math.floor(v)
    }
    Repeater {
        model: pb.n
        PaintStroke {
            required property int index
            // (bands lap by a fifth; each is set in or out at its two ends by up to about a tenth of the width)
            readonly property real lap: pb.n > 1 ? pb.step * 0.2 : 0
            readonly property real inL: (pb.rnd(index, 1) - 0.35) * Math.min(26, pb.width * 0.09)
            readonly property real inR: (pb.rnd(index, 2) - 0.35) * Math.min(30, pb.width * 0.11)
            x: inL
            y: index * pb.step - lap / 2
            width: pb.width - inL - inR
            height: pb.step + lap
            seedShift: index * 11 + 3
            color: Qt.alpha(pb.color, pb.color.a * (0.86 + 0.14 * pb.rnd(index, 3)))
        }
    }
}
