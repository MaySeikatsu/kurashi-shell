.pragma library
// The paper frame's grain (W29 washi; W41, row 447, I199): one SVG data URL per (ink, size, fibres, specks, seed, reach),
// made the first time a block asks for it and shared by every block after. Frames used to build the same string in JS
// once per block; the cost is in docs/BENCH.md ("W41 icons"). The ink is the caller's token; the rest are constants.
var tiles = {}

// The tile for these arguments, made once (the key carries every argument, so a new ink or size is a new entry).
function tile(ink, size, fibres, specks, seed, reach) {
    var key = ink.toString() + "|" + size + "|" + fibres + "|" + specks + "|" + seed + "|" + reach
    if (tiles[key] === undefined)
        tiles[key] = make(ink, size, fibres, specks, seed, reach)
    return tiles[key]
}

// A tile of `size` px with `fibres` short curved strands and `specks` dots, seeded, in the colour `ink`.
function make(ink, size, fibres, specks, seed, reach) {
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
