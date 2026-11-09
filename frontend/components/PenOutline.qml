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
    // Session 26 (perf): the lines as SVG path strings [{d, width, closed}], parsed and resampled only when the line is
    // painted. A surface that morphs passes these instead of `paths`: building the points (an arc sampled every 1.5 px)
    // on every frame cost more than painting them, and most of those frames are not painted (the cooldown below).
    property var svgs: null
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
        var w = po.pw, h = po.ph
        if (w < 1 || h < 1 || po.lineWidth <= 0) return
        var lines = po.paths
        if (!lines && po.svgs) {
            lines = []
            for (var q = 0; q < po.svgs.length; q++) {
                var subs = Pen.svgPaths(po.svgs[q].d)
                for (var u = 0; u < subs.length; u++)
                    lines.push({ points: subs[u].pts, closed: po.svgs[q].closed === undefined ? subs[u].closed : po.svgs[q].closed,
                        width: po.svgs[q].width })
            }
        }
        if (!lines) {
            var r = po.radii ? po.radii : Math.min(po.radius, w / 2, h / 2)
            if (w < 4 || h < 4) return
            lines = [{ points: po.points ? po.points : Pen.roundRect(w, h, r, po.lineWidth / 2 + po.inset, Theme.squircle), closed: true }]
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
    // The lines by content (strings: they notify only when a point moves — callers rebuild their arrays on every patch of
    // what they read, and a repaint is a commit: an idle surface must not commit, test-frame's idle check).
    readonly property string pointsKey: points ? JSON.stringify(points) : ""
    readonly property string pathsKey: paths ? JSON.stringify(paths) : ""
    readonly property string svgsKey: svgs ? JSON.stringify(svgs) : ""
    readonly property var inputs: [width, height, radius, radii, inset, color.r, color.g, color.b, lineWidth, pointsKey,
        pathsKey, svgsKey, line, pressure, breaks, fade, wobble, seed, cellX, cellY]
    // Session 26 (perf): the line is computed on the GUI thread (pen.js: wobble, pressure, breaks) and a surface that slides
    // or morphs changes its inputs every frame: kami's pen cost up to 66 ms a frame (1.4 s of GUI time in 15 s of motion,
    // against 0.08 s with a solid line). A change paints at once; changes that follow within `cooldown` ms are gathered and
    // painted when it ends, so a moving surface repaints its line about 15 times a second and once more at rest. In
    // between, the last painting is stretched to the item's size (the canvas keeps the size it was painted at, `pw` ×
    // `ph`, scaled). One single-shot timer, started by a change: nothing runs at idle (Ma).
    property real pw: 0
    property real ph: 0
    property bool dirty: false
    readonly property int cooldown: 66
    function repaintNow() {
        po.pw = po.width
        po.ph = po.height
        cv.requestPaint()
    }
    onInputsChanged: {
        if (cool.running) {
            po.dirty = true
            return
        }
        po.repaintNow()
        cool.start()
    }
    Timer {
        id: cool
        interval: po.cooldown
        onTriggered: if (po.dirty) {
            po.dirty = false
            po.repaintNow()
            cool.start()
        }
    }

    Canvas {
        id: cv
        x: -po.pad
        y: -po.pad
        width: po.pw + 2 * po.pad
        height: po.ph + 2 * po.pad
        // Stretched to the item between paints (identity at rest: pw, ph = width, height).
        transform: Scale {
            xScale: (po.width + 2 * po.pad) / Math.max(1, po.pw + 2 * po.pad)
            yScale: (po.height + 2 * po.pad) / Math.max(1, po.ph + 2 * po.pad)
        }
        // The colour's alpha is the canvas's: the ink is laid opaque, so overlapping caps never bead.
        opacity: po.color.a
        onPaint: po.paint(getContext("2d"))
    }
}
