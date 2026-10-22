import QtQuick
import "../../core"
import "../pen.js" as Pen

// Kami's hand-drawn outline (K60, docs/ux/texture.md "紙 kami"): every block's edge drawn with a pen. Two passes over one
// rounded rectangle, the second a little off the first; a seeded wobble, so the lines are the same for the same size and
// never shimmer; pen pressure (the width varies between 0.8 and 1.6 px along a pass); a small overshoot past each corner
// where the pen came back round. The ink is `Theme.fg` at 0.85 α. A small block (a key, a tile, a bar group) gets one
// quieter pass. Static: the canvas is painted once per size and colour, and nothing runs after that (Ma).
// The frame draws the outline itself (`drawsOutline`), so the block leaves its straight line out. K62: the pen's
// modifiers (pressure, breaks, fade, wobble; components/pen.js) work on top of this pen; another line style than solid
// replaces the two passes with one pass of the pen in that style, in the same ink.
FrameBase {
    id: f
    grounds: false
    drawsOutline: true

    // The closed outline of a w × h rounded rectangle inset by `i` px, as points: straight sides sampled every `step` px,
    // corners as arcs. Each side is stretched `over` px past both corners: the overshoot.
    function outline(w, h, r, i, over, step) {
        var rc = Math.max(0.5, r - i)
        var x0 = i, y0 = i, x1 = w - i, y1 = h - i
        var pts = []
        function side(ax, ay, bx, by) {
            var len = Math.hypot(bx - ax, by - ay)
            // A pill's straight end has no length: no points (it used to give NaN ones the canvas dropped).
            if (len < 1e-3) return
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

    // The pen's modifiers (K62) on top of kami's own pen; any line style but solid is drawn by the pen alone, in one pass.
    readonly property var mods: ({ line: Theme.penLine, pressure: Theme.penPressure, breaks: Theme.penBreaks,
                                   fade: Theme.penFade, wobble: Theme.penWobble })

    function paint(ctx, w, h) {
        ctx.reset()
        if (w < 8 || h < 8) return
        var pad = cv.pad
        var r = Math.min(f.radius, w / 2, h / 2)
        var seed = ((Math.round(w) * 73856093) ^ (Math.round(h) * 19349663) ^ 0x4B0A1
                    ^ (f.penSeed >= 0 ? f.penSeed : Pen.salt(f.anchor))) >>> 0
        var m = f.mods
        if (m.line !== "solid") {
            var src = Pen.roundRect(w, h, r, 1.2)
            var pts = []
            for (var q = 0; q < src.length; q++) pts.push({ x: src[q].x + pad, y: src[q].y + pad })
            Pen.outline(ctx, {
                pts: pts, width: f.small ? 0.9 : 1.3, color: Theme.fg, line: m.line, pressure: m.pressure,
                breaks: m.breaks, fade: m.fade, wobble: m.wobble, seed: seed, W: w + 2 * pad, H: h + 2 * pad
            })
            return
        }
        var R = Pen.rng(seed)
        var ink = Pen.rgb(Theme.fg)
        var passes = f.small ? [{ w: 0.8, off: 0 }] : [{ w: 1.25, off: 0 }, { w: 1.0, off: 0.7 }]
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.strokeStyle = ink
        ctx.translate(pad, pad)
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
                pts[k].dx = dx
                pts[k].dy = dy
                pts[k].p = pressure
            }
            // The modifiers along this pass: arc length, the direction and the normal at each point.
            var L = 0
            for (k = 0; k < pts.length; k++) {
                if (k > 0) L += Math.hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y)
                pts[k].s = L
            }
            var F = Pen.field(Math.max(L, 8), pass.w, m, seed + p * 7919)
            for (k = 0; k < pts.length; k++) {
                var a0 = pts[Math.max(0, k - 1)], a1 = pts[Math.min(pts.length - 1, k + 1)]
                var th = Math.atan2(a1.y - a0.y, a1.x - a0.x)
                pts[k].th = th
                pts[k].ink = F.ink(pts[k].s)
            }
            // Kami's drift, then the pen's wobble along the normal (the drift is seeded as before: the line keeps its shape).
            for (k = 0; k < pts.length; k++) {
                var o = F.off(pts[k].s)
                pts[k].x += pts[k].dx - Math.sin(pts[k].th) * o
                pts[k].y += pts[k].dy + Math.cos(pts[k].th) * o
            }
            for (var j = 0; j + 1 < pts.length; j++) {
                var a = pts[j], b = pts[j + 1]
                if (a.ink <= 0 || b.ink <= 0) continue
                ctx.beginPath()
                ctx.moveTo(a.x, a.y)
                ctx.lineTo(b.x, b.y)
                ctx.lineWidth = pass.w * (0.8 + 0.8 * (a.p + b.p) / 2) * F.mult(a.s, a.th) * Math.min(a.ink, b.ink)
                ctx.stroke()
            }
        }
        ctx.setTransform(1, 0, 0, 1, 0, 0)
        Pen.fade(ctx, w + 2 * pad, h + 2 * pad, m.fade, seed)
    }

    // One paint per size, colour and radius: the canvas is static after that.
    Canvas {
        id: cv
        // Past the face a little, so an overshoot or a wandering line is not clipped.
        readonly property real pad: 3
        x: -pad
        y: -pad
        width: f.width + 2 * pad
        height: f.height + 2 * pad
        // The ink alpha is the canvas's, not each stroke's: overlapping round caps would otherwise show as beads.
        opacity: f.small ? 0.7 : 0.85
        onPaint: f.paint(getContext("2d"), f.width, f.height)
    }
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()
    onRadiusChanged: cv.requestPaint()
    onSmallChanged: cv.requestPaint()
    onModsChanged: cv.requestPaint()
    // The salt's cell (pen.js `salt`): ints notify only when the block lands in another cell of its parent.
    readonly property int cellX: anchor ? Pen.cell(anchor.x) : 0
    readonly property int cellY: anchor ? Pen.cell(anchor.y) : 0
    onCellXChanged: cv.requestPaint()
    onCellYChanged: cv.requestPaint()
    onPenSeedChanged: cv.requestPaint()
    Connections {
        target: Theme
        function onFgChanged() { cv.requestPaint() }
    }
    Component.onCompleted: cv.requestPaint()
}
