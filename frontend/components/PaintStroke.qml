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
    // How far the stroke goes past the block's ends: a control's (a tile, a key, a bar's group) less than a surface's band.
    readonly property real over: height < 96 ? Math.max(6, Math.min(20, height * 0.45)) : Math.max(14, Math.min(52, width * 0.14))
    readonly property real room: height < 96 ? 1 : Math.min(6, height * 0.1)
    // The room the stroke has past the block's two ends before something cuts it: the nearest ancestor that clips (a
    // list in a sidebar), else the window. With less room than its overshoot the stroke starts and stops at that line
    // and its ragged ends lie inside the block instead: a stroke is never cut straight.
    property real fitL: 1e6
    property real fitR: 1e6
    function refit(): void {
        var p = ps.parent, l = 1e6, r = 1e6
        while (p) {
            if (p.clip === true) {
                var o = ps.mapToItem(p, 0, 0)
                l = o.x; r = p.width - o.x - ps.width
                break
            }
            p = p.parent
        }
        if (!p) {
            var w = ps.mapToItem(null, 0, 0)
            var win = ps.Window.window
            l = w.x; r = win ? win.width - w.x - ps.width : 1e6
        }
        ps.fitL = Math.max(0, l - 1); ps.fitR = Math.max(0, r - 1)
    }
    onWidthChanged: Qt.callLater(refit)
    onXChanged: Qt.callLater(refit)
    Component.onCompleted: Qt.callLater(refit)
    readonly property real outL: Math.min(over * 0.7, fitL)
    readonly property real outR: Math.min(over * 1.5, fitR)
    ShaderEffect {
        x: -ps.outL
        y: -ps.room
        width: ps.width + ps.outL + ps.outR
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
