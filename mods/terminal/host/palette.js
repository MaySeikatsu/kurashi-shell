// The terminal's colours (docs/ux/terminal.md "Drawing"): [foreground, background, colour 0 … colour 15] for the patched
// QMLTermWidget's setColors. The theme's own terminal table when the `theme` document carries it (`term.foreground`,
// `term.background`, `term.color0`…`term.color15`: the apps palette the shell's terminal exports use; CONTRACT-CHANGE row,
// W83). Until then a stand-in from the roles the theme does publish: the ANSI hues mixed toward the look's text colour so
// they sit in its palette, light or dark by the surface. Rule 4: no look's name in here.
.pragma library

function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }
function hex(c) {
    function h(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(c.r) + h(c.g) + h(c.b)
}

function colours(theme) {
    var t = theme.tokens || {}
    if (t["term.color0"] !== undefined && t["term.color15"] !== undefined) {
        var out = [String(t["term.foreground"] || theme.fg), String(t["term.background"] || theme.surface)]
        for (var i = 0; i < 16; i++) out.push(String(t["term.color" + i]))
        return out
    }
    var fg = theme.fg, bg = theme.surface
    var dark = lum(bg) < 0.5
    // xterm-like hues; dark looks lift them, light ones deepen them, then a little of the look's text colour.
    var base = dark
        ? ["#cc6666", "#8fbf6a", "#d8b45c", "#6f9fd8", "#b48ad0", "#5fb8b0"]
        : ["#b03a3a", "#4f7f2f", "#8a6a10", "#2f5fa8", "#7f4a9a", "#2a7f78"]
    var bright = dark
        ? ["#e08080", "#a8d888", "#ecc874", "#8ab8f0", "#cca4e6", "#7fd4cc"]
        : ["#c84a4a", "#5f9a3a", "#a8821a", "#3a72c8", "#9658b8", "#2f9a92"]
    var c = []
    c.push(hex(mix(bg, fg, 0.12)))
    for (var k = 0; k < 6; k++) c.push(hex(mix(Qt.color(base[k]), fg, 0.12)))
    c.push(hex(mix(fg, bg, 0.2)))
    c.push(hex(mix(bg, fg, 0.45)))
    for (var j = 0; j < 6; j++) c.push(hex(mix(Qt.color(bright[j]), fg, 0.08)))
    c.push(hex(fg))
    return [hex(fg), hex(bg)].concat(c)
}
