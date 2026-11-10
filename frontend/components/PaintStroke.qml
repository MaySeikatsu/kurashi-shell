import QtQuick
import "../core"

// One stroke of a brush under a block (I471b; shaders/paint_stroke.frag): fill the block with it (anchors.fill); it
// draws past the block's ends (`over`, more at its trailing end) and a little above and below (`room`). The seed is the
// block's own (its size and place), so no two strokes are alike.
Item {
    id: ps
    property color color: Qt.alpha(Theme.accent, 0.5)
    property int seedShift: 0
    // The colour the paint runs into along the stroke (the gradient mode's watercolour), and how far (0: one colour).
    property color color2: Theme.paintInto
    property real blend: Theme.paintBlend
    readonly property real over: Math.max(6, Math.min(34, height * 0.9, width * 0.22))
    readonly property real room: Math.min(5, height * 0.14)
    ShaderEffect {
        x: -ps.over * 0.7
        y: -ps.room
        width: ps.width + ps.over * 0.7 + ps.over * 1.5
        height: ps.height + 2 * ps.room
        readonly property vector4d uGeo: Qt.vector4d(width, height, ps.over,
            (Math.round(ps.width) * 7 + Math.round(ps.height) * 13 + Math.round(ps.mapToItem(null, 0, 0).x) * 3 + ps.seedShift) % 97)
        readonly property color uColor: ps.color
        readonly property vector4d uPaint: Qt.vector4d(Theme.edgeUneven, ps.room, ps.blend, 0)
        readonly property color uColor2: Qt.rgba(ps.color2.r, ps.color2.g, ps.color2.b, 1)
        fragmentShader: Qt.resolvedUrl("../shaders/paint_stroke.frag.qsb")
    }
}
