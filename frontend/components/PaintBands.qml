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
            // Each band is its own stroke of the hand: it laps the next by a third or more, is set in or out at its two
            // ends by up to a seventh of the width, sits a little high or low and leans a degree or two.
            readonly property real lap: pb.n > 1 ? pb.step * (0.3 + 0.3 * pb.rnd(index, 4)) : 0
            readonly property real inL: (pb.rnd(index, 1) - 0.4) * Math.min(44, pb.width * 0.14)
            readonly property real inR: (pb.rnd(index, 2) - 0.4) * Math.min(52, pb.width * 0.16)
            x: inL
            y: index * pb.step - lap / 2 + (pb.rnd(index, 5) - 0.5) * Math.min(8, pb.step * 0.12)
            width: pb.width - inL - inR
            height: pb.step + lap
            rotation: pb.width > 120 ? (pb.rnd(index, 6) - 0.5) * 3.4 * Math.min(1, 260 / pb.width) : 0
            seedShift: index * 11 + 3
            color: pb.color
        }
    }
}
