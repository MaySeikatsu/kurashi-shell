import QtQuick
import "../core"
import "pen.js" as Pen

// PenOutline (K62, docs/ux/texture.md "The pen"): an outline drawn with the pen — `Theme.penLine` (solid | dotted |
// dashed | broken | rough) and the modifiers `penPressure`, `penBreaks`, `penFade`, `penWobble` (components/pen.js).
// By default the outline of this item's rounded rectangle (`radius`, or one radius per corner in `radii`), the line
// `lineWidth` wide and running inside the edge as a Rectangle's border does (`inset` moves it further in: a host that
// clips its children keeps the wandering line whole). Path mode: `points` (one closed path, item coordinates, the line's
// centre) or `paths` ([{points, closed, width}], any number of closed or open lines — a surface's outline and the rule it
// hangs from) draws any other shape.
// Seeded by size and a salt (`seed`, else `anchor`'s place in its parent, read at paint time), so a line never shimmers
// and two equal blocks side by side still differ. Painted once per size, colour, path or token change; nothing runs
// after that (Ma). The canvas reaches `pad` px past the item, so a wandering or swelling line is not clipped.
Item {
    id: po
    property real radius: 0
    // [top-left, top-right, bottom-right, bottom-left], or null for `radius` at every corner.
    property var radii: null
    property real inset: 0
    property color color: Theme.outlineColor
    property real lineWidth: Theme.outlineW
    // A closed path [{x, y}, …] in item coordinates (the line's centre); null = the rounded rectangle.
    property var points: null
    // Several lines [{points, closed, width (default lineWidth)}]; overrides `points`.
    property var paths: null
    property string line: Theme.penLine
    property real pressure: Theme.penPressure
    property real breaks: Theme.penBreaks
    property real fade: Theme.penFade
    property real wobble: Theme.penWobble
    // The salt (pen.js `salt`): an explicit one (≥ 0, for a surface that knows who it is), else the place of `anchor`
    // (the block) in its parent.
    property int seed: -1
    property Item anchor: null
    readonly property real pad: 4

    function paint(ctx) {
        ctx.reset()
        var w = po.width, h = po.height
        if (w < 1 || h < 1 || po.lineWidth <= 0) return
        var lines = po.paths
        if (!lines) {
            var r = po.radii ? po.radii : Math.min(po.radius, w / 2, h / 2)
            if (w < 4 || h < 4) return
            lines = [{ points: po.points ? po.points : Pen.roundRect(w, h, r, po.lineWidth / 2 + po.inset), closed: true }]
        }
        var salt = (Pen.seedOf(w, h, 0x5E11) ^ (po.seed >= 0 ? po.seed : Pen.salt(po.anchor))) >>> 0
        for (var l = 0; l < lines.length; l++) {
            var src = lines[l].points
            if (!src || src.length < 2) continue
            var pts = []
            for (var i = 0; i < src.length; i++) pts.push({ x: src[i].x + po.pad, y: src[i].y + po.pad })
            Pen.stroke(ctx, {
                pts: pts, closed: lines[l].closed !== false, width: lines[l].width > 0 ? lines[l].width : po.lineWidth,
                color: po.color, line: po.line, pressure: po.pressure, breaks: po.breaks, wobble: po.wobble,
                seed: (salt + l * 0x9E3779B1) >>> 0
            })
        }
        Pen.fade(ctx, w + 2 * po.pad, h + 2 * po.pad, po.fade, salt)
    }

    // Every input of the drawing: one change asks for one paint.
    // The anchor's cell in its parent (ints: they notify only when the cell changes).
    readonly property int cellX: anchor ? Pen.cell(anchor.x) : 0
    readonly property int cellY: anchor ? Pen.cell(anchor.y) : 0
    readonly property var inputs: [width, height, radius, radii, inset, color.r, color.g, color.b, lineWidth, points,
        paths, line, pressure, breaks, fade, wobble, seed, cellX, cellY]
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
