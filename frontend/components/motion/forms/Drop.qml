import QtQuick
import "../../../core"

// drop (W59.5, K83; docs/ux/motion-engine.md §5 — the user's raindrop; sumi's ink-drop toasts): a bead of the look's
// accent (ink) forms on the module the card came from, falls under gravity to the card's middle (the first 35 %),
// (thrown up from a module below it: slowing to it) and lands as a ripple: a wavefront runs out from the impact and the
// card is there behind it. The ripple is water — a damped train of crests that refracts the card under it (the texture
// displaced along the ring's normal by the slope), lit on the slopes toward the K82 light and shaded on the others, the
// crests' tops inked and a thinning wash of ink behind the front; its wavelength grows as it spreads and it settles, so
// at p = 1 the card is itself. Close is the same travel backwards — the
// card draws in to a bead that rises home — or, for a toast or a card without an origin, the bead evaporates where it
// formed (shrinks and thins). One fragment pass over the capture and the drop's path; a reversal keeps the direction it
// started with.
// Params (`motion.form_params.drop`): ring 2–4 px (3: the crest's width), refraction 0–1 (0.6).
SheetForm {
    id: drop

    readonly property real ringPx: params && params.ring > 0 ? Math.max(2, Math.min(4, params.ring)) : 3
    readonly property real refraction: params && params.refraction !== undefined
        ? Math.max(0, Math.min(1, params.refraction)) : 0.6
    readonly property color ink: Theme.accent
    // The bead's radius (px).
    readonly property real bead: 6

    // Card px (the capture's frame): the impact (the card's middle) and where the bead forms — the origin's middle, or
    // without one (§10 "origin gone") 48 px above the card: rain falls down the screen whatever edge the card is on.
    readonly property bool hasOrigin: origin.width > 0 || origin.height > 0
    readonly property point impact: Qt.point(area.width / 2, area.height / 2)
    readonly property point well: hasOrigin
        ? Qt.point(origin.x + origin.width / 2 - area.x, origin.y + origin.height / 2 - area.y)
        : Qt.point(impact.x, -48)
    readonly property bool evaporates: direction === "close" && (surface === "toast" || !hasOrigin)
    readonly property real fall: Math.hypot(impact.x - well.x, impact.y - well.y)
    readonly property point dir: fall > 0.5 ? Qt.point((impact.x - well.x) / fall, (impact.y - well.y) / fall)
        : Qt.point(0, 1)
    // From a module under the card (a dock, a bottom bar) the bead is thrown up: it slows to the impact instead.
    readonly property bool thrown: dir.y < -0.3
    // The front's last radius: past the card's farthest corner by the crest's whole width.
    readonly property real reach: Math.hypot(area.width / 2, area.height / 2) + wavelength / 2 + 2
    // The ripple's wavelength (px): it grows as the ring spreads (longer waves run ahead: dispersion).
    readonly property real wavelength: Math.max(10, ringPx * 4.5) * (0.85 + 0.5 * wave)

    // The bead at p: its middle (card px), radius, elongation along its fall, and alpha.
    readonly property var drip: {
        var b = { x: well.x, y: well.y, r: 0, stretch: 1, a: 0 }
        if (p >= 0.39) return b
        if (evaporates) {
            // forms at the impact out of the drawn-in card, then thins away (rising a little, as vapour does)
            var e = sub(p, 0, 0.35)
            b.x = impact.x; b.y = impact.y - 8 * (1 - e)
            b.r = bead * Math.sqrt(ease(e)); b.a = ease(sub(p, 0, 0.3)) * (1 - sub(p, 0.35, 0.39)); b.stretch = 1
            return b
        }
        // forms on the origin, falls on gravity's curve (the `drop` preset's fall: a little start speed, then g) — or,
        // thrown up, the same curve backwards (fast off the module, slowing to the impact)
        var grow = ease(sub(p, 0, 0.06))
        var s = sub(p, 0.03, 0.35)
        var t = thrown ? 1 - s : s
        var f = 0.12 * t + 0.88 * t * t
        if (thrown) f = 1 - f
        b.x = well.x + (impact.x - well.x) * f
        b.y = well.y + (impact.y - well.y) * f
        // stretched by its speed (area kept), more on a long fall; squashed flat for a moment on impact
        var v = (0.12 + 1.76 * t) / 1.88
        b.stretch = 1 + 0.55 * v * Math.min(1, fall / 160) * (s > 0 ? 1 : 0)
        var hit = sub(p, 0.35, 0.39)
        b.r = bead * grow * (1 + 0.5 * hit)
        b.stretch = b.stretch * (1 - hit) + 0.55 * hit
        b.a = grow * (1 - hit)
        return b
    }
    // The ripple: the front's radius and the crests' height (0 flat … 1).
    readonly property real wave: sub(p, 0.35, 1)
    readonly property real front: p < 0.35 ? 0 : bead * 0.8 + (reach - bead * 0.8) * (1 - Math.pow(1 - wave, 2.2))
    readonly property real amp: p < 0.35 ? 0 : Math.pow(1 - wave, 1.4) * Math.min(1, 0.35 + wave * 6)

    // The pass covers the card and the bead's path (the bead starts outside the card, on its module).
    readonly property real pad: bead * 3
    readonly property rect box: {
        var x0 = Math.min(0, well.x - pad), y0 = Math.min(0, well.y - pad)
        var x1 = Math.max(area.width, well.x + pad), y1 = Math.max(area.height, well.y + pad)
        return Qt.rect(x0, y0, x1 - x0, y1 - y0)
    }

    SheetForm.Pass {
        host: drop
        name: "drop"
        x: drop.area.x + drop.box.x
        y: drop.area.y + drop.box.y
        width: drop.box.width
        height: drop.box.height
        uCover: Qt.vector4d(drop.ink.r, drop.ink.g, drop.ink.b, 1)
        uMisc: Qt.vector4d(drop.fillAlpha, drop.p, drop.box.width, drop.box.height)
        u0: Qt.vector4d(drop.dir.x, drop.dir.y, drop.impact.x, drop.impact.y)
        u1: Qt.vector4d(drop.drip.x, drop.drip.y, drop.drip.r, drop.drip.stretch)
        u2: Qt.vector4d(drop.drip.a, drop.wavelength, drop.front, drop.ringPx)
        u3: Qt.vector4d(drop.amp, 10 * drop.refraction, drop.box.x, drop.box.y)
    }
}
