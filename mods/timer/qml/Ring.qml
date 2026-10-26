import QtQuick
import "Timer.js" as T

// The timer's ring: `share` (0..1) of a circle, from 12 o'clock clockwise, over a track of the same circle. An empty share
// still reads as a ring. It repaints only when its share or its colours change, so it costs a frame per second at most,
// and only while a countdown is on screen (the clock that moves `share` runs only then).
Canvas {
    id: ring
    property real share: 0
    property color stroke: "#e9e4d8"
    property color track: "#5a5560"
    property real lineWidth: 2

    onShareChanged: ring.requestPaint()
    onStrokeChanged: ring.requestPaint()
    onTrackChanged: ring.requestPaint()
    onLineWidthChanged: ring.requestPaint()
    onWidthChanged: ring.requestPaint()
    onHeightChanged: ring.requestPaint()
    Component.onCompleted: ring.requestPaint()

    onPaint: {
        var ctx = ring.getContext("2d")
        ctx.clearRect(0, 0, ring.width, ring.height)
        var c = Math.min(ring.width, ring.height) / 2
        var r = c - ring.lineWidth / 2
        ctx.lineWidth = ring.lineWidth
        ctx.strokeStyle = T.css(ring.track)
        ctx.beginPath()
        ctx.arc(c, c, r, 0, 2 * Math.PI)
        ctx.stroke()
        if (ring.share > 0) {
            ctx.strokeStyle = T.css(ring.stroke)
            ctx.beginPath()
            ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(1, ring.share))
            ctx.stroke()
        }
    }
}
