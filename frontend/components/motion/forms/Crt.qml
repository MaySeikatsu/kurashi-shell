import QtQuick
import "../../../core"

// crt (W59.5, K83; docs/ux/motion-engine.md §5 — the user's old CRT TV; terminal's phosphor, D4): the card is a picture
// on a tube. On: the beam lights a dot in the card's middle (the first 5 %), the dot draws out into a horizontal line
// across the card (to 40 %), then the picture opens from the line to its full height (to 100 %) — bright at first, as a
// tube is when its whole picture is squeezed into a few lines, with a glow round the line, a slight barrel, scanlines;
// all of it fades so that at p = 1 the card is itself. Off: the picture collapses to the line (40 % of the travel),
// the line to a dot (to 65 %), and the dot's afterglow fades over the rest (phosphor's close is 340 ms linear: 120 ms).
// One fragment pass over the capture; a reversal keeps the direction it started with, so it continues from where it is.
// Flash-safe (brief §11): the picture never brightens by more than 20 % toward white and only once per transition (up
// as it squeezes, back down as it opens); the bright beam is a line or a dot, never an area; the glow round it adds at
// most 20 % over what lies beneath. No flicker, no roll. Reduce motion and photosensitivity never reach this form (the
// daemon resolves `flash` forms away: K83 D1).
// Params (`motion.form_params.crt`): glow 0–1 (0.6: the bloom's reach), scanlines 0–1 (0.5: their depth).
SheetForm {
    id: crt

    readonly property real glow: params && params.glow !== undefined ? Math.max(0, Math.min(1, params.glow)) : 0.6
    readonly property real scan: params && params.scanlines !== undefined ? Math.max(0, Math.min(1, params.scanlines)) : 0.5
    readonly property bool closing: direction === "close"

    // The beam: the brighter of the card's ink and its fill, a little hotter (on a phosphor terminal: its green).
    function lum(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    readonly property color ink: lum(Theme.fg) >= lum(Theme.surface) ? Theme.fg : Theme.surface
    readonly property color beam: Qt.rgba(ink.r + (1 - ink.r) * 0.35, ink.g + (1 - ink.g) * 0.35, ink.b + (1 - ink.b) * 0.35, 1)

    // The dot's radius and the line's half thickness (px).
    readonly property real dot: 2.5
    readonly property real line: 1.5
    // The state of the tube at p: half extents of the lit rect, how much of it is the beam (vs the picture), the
    // picture's brightening, the glow, the barrel, the scanlines and the overall intensity (the dot's rise and afterglow).
    readonly property var tube: {
        var W = area.width / 2, H = area.height / 2
        var t = { hw: W, hh: H, beam: 0, boost: 0, glow: 0, barrel: 0, scan: 0, lum: 1 }
        var s
        if (!closing) {
            if (p < 0.05) {
                s = ease(sub(p, 0, 0.05))
                t.hw = t.hh = Math.max(0.5, dot * s); t.beam = 1; t.glow = 1; t.lum = s
                t.boost = 0.2; t.barrel = 1; t.scan = 1
            } else if (p < 0.4) {
                s = ease(sub(p, 0.05, 0.4))
                t.hw = dot + (W - dot) * s; t.hh = dot + (line - dot) * s; t.beam = 1; t.glow = 1
                t.boost = 0.2; t.barrel = 1; t.scan = 1
            } else {
                s = sub(p, 0.4, 1)
                // (the picture opens fast and settles: a tube's vertical deflection swinging up)
                var o = 1 - Math.pow(1 - s, 3)
                t.hh = line + (H - line) * o
                t.beam = 1 - smooth01(s / 0.3)
                t.glow = 1 - smooth01(s / 0.4)
                var fade = 1 - ease(s)
                t.boost = 0.2 * fade; t.barrel = fade; t.scan = fade
            }
        } else {
            var q = 1 - p
            if (q < 0.4) {
                s = sub(q, 0, 0.4)
                // (collapses accelerating: the deflection gives out)
                var c = s * s * s
                t.hh = H + (line - H) * c
                t.beam = smooth01((s - 0.7) / 0.3)
                t.glow = smooth01((s - 0.6) / 0.4)
                var rise = ease(s)
                t.boost = 0.2 * rise; t.barrel = rise; t.scan = rise
            } else if (q < 0.65) {
                s = ease(sub(q, 0.4, 0.65))
                t.hw = W + (dot - W) * s; t.hh = line + (dot - line) * s; t.beam = 1; t.glow = 1
                t.boost = 0.2; t.barrel = 1; t.scan = 1
            } else {
                s = sub(q, 0.65, 1)
                // the afterglow: the dot dims (phosphor decays fast, then lingers) and shrinks a little
                t.hw = t.hh = dot * (1 - 0.4 * s); t.beam = 1; t.glow = 1
                t.lum = Math.pow(1 - s, 2.2)
                t.boost = 0.2; t.barrel = 1; t.scan = 1
            }
        }
        return t
    }

    // The glow's reach (px), and the room the pass takes round the card for it (the line runs to the card's edges).
    readonly property real reach: 3 + 9 * glow
    readonly property real margin: Math.ceil(2.5 * reach)

    SheetForm.Pass {
        host: crt
        name: "crt"
        x: crt.area.x - crt.margin
        y: crt.area.y - crt.margin
        width: crt.area.width + 2 * crt.margin
        height: crt.area.height + 2 * crt.margin
        u0: Qt.vector4d(crt.area.width / 2, crt.area.height / 2, crt.tube.hw, crt.tube.hh)
        u1: Qt.vector4d(crt.tube.beam, crt.tube.boost, Math.min(0.2, crt.tube.glow * 0.2) * crt.tube.lum, crt.reach)
        u2: Qt.vector4d(crt.beam.r, crt.beam.g, crt.beam.b, crt.tube.scan * crt.scan)
        u3: Qt.vector4d(crt.tube.barrel * 0.12, 3, crt.tube.lum, crt.margin)
    }
}
