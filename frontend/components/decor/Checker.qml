import QtQuick
import "../../core"

// Checker (W53.1): the bevel era's dither — every other pixel the bevel's highlight over the face (9x's scroll-bar track,
// a latched toolbar button). Painted once per size and colour.
Canvas {
    id: ck
    property color base: Theme.surface
    property color dots: Theme.bevelLight
    readonly property string paintKey: [base, dots, width, height].join("|")
    onPaintKeyChanged: requestPaint()
    onPaint: {
        var g = getContext("2d")
        g.reset()
        g.fillStyle = base
        g.fillRect(0, 0, width, height)
        g.fillStyle = g.createPattern(dots, Qt.Dense4Pattern)
        g.fillRect(0, 0, width, height)
    }
}
