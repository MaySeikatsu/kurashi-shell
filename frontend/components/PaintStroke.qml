import QtQuick
import "../core"

// One stroke of a brush under a block (I471b; shaders/paint_stroke.frag): fill the block with it (anchors.fill); it
// draws past the block's ends (`over`, more at its trailing end) and a little above and below (`room`). The seed is the
// block's own (its size and place), so no two strokes are alike.
Item {
    id: ps
    property color color: Qt.alpha(Theme.accent, 0.5)
    property int seedShift: 0
    // The stroke's own seed, drawn once: it must not follow the size (a surface that grows or morphs would get a new
    // stroke every frame, which reads as stutter).
    readonly property int seed0: Math.floor(Math.random() * 89)
    // The colour the paint runs into along the stroke (the gradient mode's watercolour), and how far (0: one colour).
    property color color2: Theme.paintInto
    property real blend: Theme.paintBlend
    // How far the stroke goes past the block's ends: a control's (a tile, a key, a bar's group) a little, so strokes side
    // by side stay apart; a surface's band further.
    readonly property real over: height < 96 ? Math.max(4, Math.min(14, height * 0.3)) : Math.max(14, Math.min(52, width * 0.14))
    // (the stroke is a little lower than a control's box: neighbours one over another do not touch)
    readonly property real room: height < 96 ? -Math.min(3, height * 0.06) : Math.min(6, height * 0.1)
    ShaderEffect {
        x: -ps.over * 0.7
        y: -ps.room
        width: ps.width + ps.over * 0.7 + ps.over * 1.5
        height: ps.height + 2 * ps.room
        readonly property vector4d uGeo: Qt.vector4d(width, height, ps.over,
            (ps.seed0 + ps.seedShift) % 97)
        readonly property color uColor: ps.color
        readonly property vector4d uPaint: Qt.vector4d(Theme.edgeUneven, Math.max(2, Math.abs(ps.room)), ps.blend, 0)
        readonly property vector4d uScene: { var o = ps.mapToItem(null, 0, 0); return Qt.vector4d(o.x + x, o.y + y, 0, 0) }
        readonly property color uColor2: Qt.rgba(ps.color2.r, ps.color2.g, ps.color2.b, 1)
        fragmentShader: Qt.resolvedUrl("../shaders/paint_stroke.frag.qsb")
    }
}
