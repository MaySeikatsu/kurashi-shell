import QtQuick
import "../core"
import "pen.js" as Pen

// PenOutline (K62, docs/ux/texture.md "The pen"): an outline drawn with the pen — `Theme.penLine` (solid | dotted |
// dashed | broken | rough) and the modifiers `penPressure`, `penBreaks`, `penFade`, `penWobble` (components/pen.js).
// By default the outline of this item's rounded rectangle (`radius`), the line `lineWidth` wide and running inside the
// edge as a Rectangle's border does; `points` (a closed path, item coordinates) draws any other shape. Seeded by size:
// the same size draws the same line, never shimmering. Painted once per size, colour or token change; nothing runs
// after that (Ma). The canvas reaches `pad` px past the item, so a wandering or swelling line is never clipped.
Item {
    id: po
    property real radius: 0
    property color color: Theme.outlineColor
    property real lineWidth: Theme.outlineW
    // A closed path [{x, y}, …] in item coordinates (the line's centre); null = the rounded rectangle.
    property var points: null
    property string line: Theme.penLine
    property real pressure: Theme.penPressure
    property real breaks: Theme.penBreaks
    property real fade: Theme.penFade
    property real wobble: Theme.penWobble
    readonly property real pad: 4

    function paint(ctx) {
        ctx.reset()
        var w = po.width, h = po.height
        if (w < 4 || h < 4 || po.lineWidth <= 0) return
        var src = po.points ? po.points : Pen.roundRect(w, h, Math.min(po.radius, w / 2, h / 2), po.lineWidth / 2)
        var pts = []
        for (var i = 0; i < src.length; i++) pts.push({ x: src[i].x + po.pad, y: src[i].y + po.pad })
        Pen.outline(ctx, {
            pts: pts, width: po.lineWidth, color: po.color, line: po.line,
            pressure: po.pressure, breaks: po.breaks, fade: po.fade, wobble: po.wobble,
            seed: Pen.seedOf(w, h, 0x5E11), W: w + 2 * po.pad, H: h + 2 * po.pad
        })
    }

    // Every input of the drawing: one change asks for one paint.
    readonly property var inputs: [width, height, radius, color.r, color.g, color.b, lineWidth, points, line, pressure,
        breaks, fade, wobble]
    onInputsChanged: cv.requestPaint()

    Canvas {
        id: cv
        x: -po.pad
        y: -po.pad
        width: po.width + 2 * po.pad
        height: po.height + 2 * po.pad
        // The colour's alpha is the canvas's: the ink is laid opaque, so overlapping caps never bead.
        opacity: po.color.a
        onPaint: po.paint(getContext("2d"))
    }
}
