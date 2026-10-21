import QtQuick
import "../../core"

// Washi paper (look washi, W29): a very fine fibre grain and a soft inner hairline in the ink colour (`Theme.fg`, low
// alpha), a stronger grain on a surface's ground (the lock, the greeter). The grain is one small tile — an SVG made once
// per ink colour from a fixed seed, so every block shows the same sheet — that Qt's image cache shares between all
// blocks; it tiles seamlessly (a fibre that crosses an edge is drawn again on the other side) and never animates.
// Small blocks (bar groups, keys) get it fainter: more on a 20 px key reads as dirt. Tokens only (rule 4).
FrameBase {
    id: f
    // The ground is paper: the surface's colour under a stronger grain (it replaces the chrome's ruled ground).
    grounds: true

    // A tile of `size` px with `fibres` short curved strands and `specks` dots, seeded, in the colour `ink`.
    function tile(ink, size, fibres, specks, seed, reach) {
        var s = seed >>> 0
        function rnd() {   // mulberry32: the same paper every time
            s = (s + 0x6D2B79F5) >>> 0
            var t = s
            t = Math.imul(t ^ (t >>> 15), t | 1)
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
        function n(v) { return Math.round(v * 10) / 10 }
        var out = []
        // Every copy of a mark that reaches into the tile, so the tile repeats without a seam.
        function copies(into, x, y, r, draw) {
            for (var dx = -size; dx <= size; dx += size)
                for (var dy = -size; dy <= size; dy += size)
                    if (x + dx + r > 0 && x + dx - r < size && y + dy + r > 0 && y + dy - r < size) into.push(draw(x + dx, y + dy))
        }
        for (var i = 0; i < fibres; i++) {
            var x = rnd() * size, y = rnd() * size
            var len = reach * (0.35 + rnd() * 0.65), a = rnd() * Math.PI
            var bend = (rnd() - 0.5) * len * 0.6
            var ex = Math.cos(a) * len, ey = Math.sin(a) * len
            var cx = ex / 2 - Math.sin(a) * bend, cy = ey / 2 + Math.cos(a) * bend
            var w = n(0.35 + rnd() * 0.45), o = n(0.3 + rnd() * 0.7)
            copies(out, x, y, len, function (px, py) {
                return '<path d="M' + n(px) + ' ' + n(py) + 'q' + n(cx) + ' ' + n(cy) + ' ' + n(ex) + ' ' + n(ey)
                    + '" stroke-width="' + w + '" stroke-opacity="' + o + '"/>'
            })
        }
        var dots = []
        for (var j = 0; j < specks; j++) {
            var sx = rnd() * size, sy = rnd() * size, r = n(0.3 + rnd() * 0.5), so = n(0.2 + rnd() * 0.6)
            copies(dots, sx, sy, r, function (px, py) {
                return '<circle cx="' + n(px) + '" cy="' + n(py) + '" r="' + r + '" fill-opacity="' + so + '"/>'
            })
        }
        var hex = ink.toString()
        var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + size + '" height="' + size + '">'
            + '<g fill="none" stroke="' + hex + '" stroke-linecap="round">' + out.join("") + '</g>'
            + '<g fill="' + hex + '">' + dots.join("") + '</g></svg>'
        return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg)
    }
    // The ink without its alpha, so one tile serves every opacity (the layers set theirs).
    readonly property color ink: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 1)
    readonly property string fine: f.tile(f.ink, 160, 60, 80, 7, 16)
    readonly property string coarse: f.ground ? f.tile(f.ink, 256, 70, 0, 23, 46) : ""

    // ---- a block: the grain inside the corners' curve, and a soft inner hairline (the sheet's edge) ----
    Image {
        visible: !f.ground && f.fine !== ""
        anchors.fill: parent
        // Clear of the rounded corners (r·(1 − 1/√2)), so no grain shows outside the block.
        anchors.margins: Math.ceil(f.radius * 0.3)
        source: f.fine
        sourceSize: Qt.size(160, 160)
        fillMode: Image.Tile
        smooth: false
        opacity: f.small ? 0.07 : 0.11
    }
    Rectangle {
        visible: !f.ground
        anchors.fill: parent
        anchors.margins: 1.5
        radius: Math.max(0, f.radius - 1.5)
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(f.ink, f.small ? 0.07 : 0.1)
    }

    // ---- the ground: the surface's paper, the fine grain and longer fibres over it ----
    Rectangle {
        visible: f.ground
        anchors.fill: parent
        color: Theme.surface
    }
    Image {
        visible: f.ground
        anchors.fill: parent
        source: f.ground ? f.fine : ""
        sourceSize: Qt.size(160, 160)
        fillMode: Image.Tile
        smooth: false
        opacity: 0.14
    }
    Image {
        visible: f.ground
        anchors.fill: parent
        source: f.coarse
        sourceSize: Qt.size(256, 256)
        fillMode: Image.Tile
        opacity: 0.1
    }
}
