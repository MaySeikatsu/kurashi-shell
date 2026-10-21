import QtQuick
import "../../core"

// Kami's hand-drawn outline (K60, docs/ux/texture.md "紙 kami"): every block's edge drawn with a pen. Two passes over one
// rounded rectangle, the second a little off the first; a seeded wobble, so the lines are the same for the same size and
// never shimmer; pen pressure (the width varies between 0.8 and 1.6 px along a pass); a small overshoot past each corner
// where the pen came back round. The ink is `Theme.fg` at 0.85 α. A small block (a key, a tile, a bar group) gets one
// quieter pass. Static: the canvas is painted once per size and colour, and nothing runs after that (Ma).
// The frame draws the outline itself (`drawsOutline`), so the block leaves its straight line out.
FrameBase {
    id: f
    grounds: false
    drawsOutline: true

    // A seeded generator (mulberry32): the same numbers for the same size.
    function rng(seed) {
        var s = seed >>> 0
        return function () {
            s = (s + 0x6D2B79F5) >>> 0
            var t = s
            t = Math.imul(t ^ (t >>> 15), t | 1)
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
    }

    // The closed outline of a w × h rounded rectangle inset by `i` px, as points: straight sides sampled every `step` px,
    // corners as arcs. Each side is stretched `over` px past both corners: the overshoot.
    function outline(w, h, r, i, over, step) {
        var rc = Math.max(0.5, r - i)
        var x0 = i, y0 = i, x1 = w - i, y1 = h - i
        var pts = []
        function side(ax, ay, bx, by) {
            var len = Math.hypot(bx - ax, by - ay)
            var ux = (bx - ax) / len, uy = (by - ay) / len
            var n = Math.max(1, Math.round(len / step))
            var a0 = -over, a1 = len + over
            for (var k = 0; k <= n; k++) {
                var d = a0 + (a1 - a0) * k / n
                pts.push({ x: ax + ux * d, y: ay + uy * d })
            }
        }
        function arc(cx, cy, a0, a1) {
            var n = Math.max(2, Math.round((a1 - a0) * rc / step))
            for (var k = 1; k <= n; k++) {
                var a = a0 + (a1 - a0) * k / n
                pts.push({ x: cx + rc * Math.cos(a), y: cy + rc * Math.sin(a) })
            }
        }
        if (rc <= 0.5) {
            side(x0, y0, x1, y0); side(x1, y0, x1, y1); side(x1, y1, x0, y1); side(x0, y1, x0, y0)
            return pts
        }
        side(x0 + rc, y0, x1 - rc, y0)
        arc(x1 - rc, y0 + rc, -Math.PI / 2, 0)
        side(x1, y0 + rc, x1, y1 - rc)
        arc(x1 - rc, y1 - rc, 0, Math.PI / 2)
        side(x1 - rc, y1, x0 + rc, y1)
        arc(x0 + rc, y1 - rc, Math.PI / 2, Math.PI)
        side(x0, y1 - rc, x0, y0 + rc)
        arc(x0 + rc, y0 + rc, Math.PI, Math.PI * 1.5)
        return pts
    }

    function paint(ctx, w, h) {
        ctx.clearRect(0, 0, w, h)
        if (w < 8 || h < 8) return
        var r = Math.min(f.radius, w / 2, h / 2)
        var seed = (Math.round(w) * 73856093) ^ (Math.round(h) * 19349663) ^ 0x4B0A1
        var R = rng(seed)
        var c = Theme.fg
        var rgb = Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255)
        var passes = f.small ? [{ w: 0.8, off: 0 }] : [{ w: 1.25, off: 0 }, { w: 1.0, off: 0.7 }]
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        for (var p = 0; p < passes.length; p++) {
            var pass = passes[p]
            var inset = 0.9 + pass.off
            var pts = outline(w, h, r, inset, f.small ? 0 : 2.5, 6)
            // The wobble: a slow drift (a smoothed walk) of at most ~0.7 px, so the line bends like a hand, not a jitter.
            var dx = 0, dy = 0, pressure = 0.5
            for (var k = 0; k < pts.length; k++) {
                dx = dx * 0.7 + (R() - 0.5) * 0.5
                dy = dy * 0.7 + (R() - 0.5) * 0.5
                pressure = Math.min(1, Math.max(0, pressure + (R() - 0.5) * 0.35))
                pts[k].x += dx
                pts[k].y += dy
                pts[k].p = pressure
            }
            for (var j = 0; j + 1 < pts.length; j++) {
                var a = pts[j], b = pts[j + 1]
                ctx.beginPath()
                ctx.moveTo(a.x, a.y)
                ctx.lineTo(b.x, b.y)
                ctx.lineWidth = pass.w * (0.8 + 0.8 * (a.p + b.p) / 2)
                ctx.strokeStyle = "rgb(" + rgb + ")"
                ctx.stroke()
            }
        }
    }

    // One paint per size, colour and radius: the canvas is static after that.
    Canvas {
        id: cv
        anchors.fill: parent
        // The ink alpha is the canvas's, not each stroke's: overlapping round caps would otherwise show as beads.
        opacity: f.small ? 0.7 : 0.85
        onPaint: f.paint(getContext("2d"), width, height)
    }
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()
    onRadiusChanged: cv.requestPaint()
    onSmallChanged: cv.requestPaint()
    Connections {
        target: Theme
        function onFgChanged() { cv.requestPaint() }
    }
    Component.onCompleted: cv.requestPaint()
}
