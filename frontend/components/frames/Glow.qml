import QtQuick

// A soft elliptical glow for frame grounds (W25): a radial gradient from `color` at `alpha` in the centre to nothing
// at the edge, stretched to the item's box. One paint per size and colour (a gradient rectangle in an ellipse leaves
// a hard rim; this has none).
Canvas {
    id: gl
    property color color: "white"
    property real alpha: 0.3
    // Where the glow is still at half strength (0..1 of the radius).
    property real mid: 0.45
    onColorChanged: requestPaint()
    onAlphaChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var g = getContext("2d")
        g.reset()
        if (width <= 0 || height <= 0) return
        var r = width / 2
        g.save()
        g.scale(1, height / width)
        var gr = g.createRadialGradient(r, r, 0, r, r, r)
        gr.addColorStop(0, Qt.alpha(gl.color, gl.alpha))
        gr.addColorStop(gl.mid, Qt.alpha(gl.color, gl.alpha * 0.5))
        gr.addColorStop(1, Qt.alpha(gl.color, 0))
        g.fillStyle = gr
        g.fillRect(0, 0, width, width)
        g.restore()
    }
}
