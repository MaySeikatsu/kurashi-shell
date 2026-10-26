import QtQuick
import "Timer.js" as T

// The timer's ring: the remaining `share` (0..1) of a circle, drawn from 12 o'clock clockwise in `stroke` (the accent for a
// focus, the tertiary colour for a break, dim while paused), over the whole circle in `track` at a low alpha, so the time that
// is gone reads as the empty part of the ring (50 % is half the arc, 95 % nearly all of it). It repaints only when its share
// or its colours change, so it costs a frame per second at most, and only while a countdown is on screen (the clock that moves
// `share` runs only then).
Canvas {
    id: ring
    property real share: 0
    property color stroke: "#c9404b"
    property color track: "#5a5560"
    // The dim full circle under the arc: the track colour at this alpha.
    property real trackAlpha: 0.3
    property real lineWidth: 2

    onShareChanged: ring.requestPaint()
    onStrokeChanged: ring.requestPaint()
    onTrackChanged: ring.requestPaint()
    onTrackAlphaChanged: ring.requestPaint()
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
        ctx.lineCap = "butt"
        ctx.strokeStyle = T.css(ring.track, ring.trackAlpha)
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
