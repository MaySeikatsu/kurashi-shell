import QtQuick
import "../../../core"

// drop (W59.5, K83; docs/ux/motion-engine.md §5 — the user's raindrop; sumi's ink-drop toasts). S21 (the user: slower,
// more morphing, a real fall, a drop that gathers first): the pressed module's own shape fills with ink and draws itself
// together into a bead hanging under it (the first 16 %), the bead swells into a little bulge for a moment as a real drop
// does before it lets go (to 25 %), then falls from rest under gravity — slow at first, faster and longer as it goes —
// to the card's middle (to 50 %), squashes flat on impact and lands as a ripple: a wavefront runs out from the impact and
// the card is there behind it. The ripple is water — a damped train of crests that refracts the card under it (the
// texture displaced along the ring's normal by the slope), lit on the slopes toward the K82 light and shaded on the
// others, the crests' tops inked and a thinning wash of ink behind the front; its wavelength grows as it spreads and it
// settles, so at p = 1 the card is itself. Close is the same story backwards — the card draws in to a bead that rises
// home and spreads back into its module — or, for a toast or a card without an origin, the bead evaporates where it
// formed (shrinks and thins). One fragment pass over the capture and the drop's path; a reversal keeps the direction it
// started with. Its pace (forms meta, 1.9) gives the story its time on any profile.
// Params (`motion.form_params.drop`): ring 2–4 px (3: the crest's width), refraction 0–1 (0.6).
SheetForm {
    id: drop

    readonly property real ringPx: params && params.ring > 0 ? Math.max(2, Math.min(4, params.ring)) : 3
    readonly property real refraction: params && params.refraction !== undefined
        ? Math.max(0, Math.min(1, params.refraction)) : 0.6
    readonly property color ink: Theme.accent
    // The bead's radius (px).
    readonly property real bead: 6
    // Where the user pressed (FormHost's `pressAt`, host px; NaN = none): without an origin the bead forms there.
    property point pressAt: Qt.point(NaN, NaN)
    readonly property bool hasPress: !isNaN(pressAt.x) && !isNaN(pressAt.y)

    // The story's beats (fractions of p): gathered, let go, impact, flat.
    readonly property real tGather: 0.16
    readonly property real tLetGo: 0.25
    readonly property real tImpact: 0.5
    readonly property real tFlat: 0.54

    // Card px (the capture's frame): the impact (the card's middle) and where the bead forms — the origin's middle, the
    // press, or without either (§10 "origin gone") 48 px above the card: rain falls down the screen whatever edge.
    readonly property bool hasOrigin: origin.width > 0 || origin.height > 0
    readonly property point impact: Qt.point(area.width / 2, area.height / 2)
    readonly property rect from: hasOrigin ? Qt.rect(origin.x - area.x, origin.y - area.y, origin.width, origin.height)
        : hasPress ? Qt.rect(pressAt.x - area.x - bead, pressAt.y - area.y - bead, 2 * bead, 2 * bead)
        : Qt.rect(impact.x - bead, -48 - bead, 2 * bead, 2 * bead)
    readonly property point well: Qt.point(from.x + from.width / 2, from.y + from.height / 2)
    readonly property bool evaporates: direction === "close" && (surface === "toast" || (!hasOrigin && !hasPress))
    readonly property real fall: Math.hypot(impact.x - well.x, impact.y - well.y)
    readonly property point dir: fall > 0.5 ? Qt.point((impact.x - well.x) / fall, (impact.y - well.y) / fall)
        : Qt.point(0, 1)
    // The screen axis nearest the fall: the module's shape gathers in it (an axis-aligned pill), then turns to the fall.
    readonly property point axis: Math.abs(dir.y) >= Math.abs(dir.x) ? Qt.point(0, dir.y < 0 ? -1 : 1)
        : Qt.point(dir.x < 0 ? -1 : 1, 0)
    // From a module under the card (a dock, a bottom bar) the bead is thrown up: it slows to the impact instead.
    readonly property bool thrown: dir.y < -0.3
    // Where the gathered bead hangs: just past the module's edge toward the fall.
    readonly property real fromAlong: axis.x !== 0 ? from.width / 2 : from.height / 2
    readonly property real fromAcross: axis.x !== 0 ? from.height / 2 : from.width / 2
    readonly property point hang: Qt.point(well.x + axis.x * (fromAlong + bead * 0.6), well.y + axis.y * (fromAlong + bead * 0.6))
    // The front's last radius: past the card's farthest corner by the crest's whole width.
    readonly property real reach: Math.hypot(area.width / 2, area.height / 2) + wavelength / 2 + 2
    // The ripple's wavelength (px): it grows as the ring spreads (longer waves run ahead: dispersion).
    readonly property real wavelength: Math.max(10, ringPx * 4.5) * (0.85 + 0.5 * wave)

    function mixv(a, b, k) { return a + (b - a) * k }
    // The bead at p: its middle (card px), radius (the highlight's size), its frame (`fx, fy`: along the fall), its box in
    // that frame (half along, half across, corner radius, tail) and alpha.
    readonly property var drip: {
        var b = { x: well.x, y: well.y, r: 0, fx: axis.x, fy: axis.y, along: 0, across: 0, corner: 0, tail: 0, a: 0 }
        if (p >= tFlat) return b
        if (evaporates) {
            // forms at the impact out of the drawn-in card, then thins away (rising a little, as vapour does)
            var e = sub(p, 0, 0.35)
            var er = bead * Math.sqrt(ease(e))
            b.x = impact.x; b.y = impact.y - 8 * (1 - e)
            b.r = er; b.along = er; b.across = er; b.corner = er
            b.a = ease(sub(p, 0, 0.3)) * (1 - sub(p, 0.35, 0.39))
            return b
        }
        var R = bead * 1.2
        if (p < tGather) {
            // the module's shape fills with ink and draws together into a bead under it
            var g = ease(sub(p, 0, tGather))
            // (the ink covers the module at once: the module's own face has gone to the sheet by then)
            b.a = 0.92 * Math.min(1, p / 0.01)
            b.x = mixv(well.x, hang.x, g); b.y = mixv(well.y, hang.y, g)
            b.along = mixv(fromAlong, bead, g); b.across = mixv(fromAcross, bead, g)
            b.corner = mixv(Math.min(fromAlong, fromAcross), bead, g)
            b.r = Math.min(b.along, b.across)
            return b
        }
        // swelling into a bulge, its neck toward the module, a small wobble as it gathers its weight
        var k = sub(p, tGather, tLetGo), ke = ease(k)
        var r = mixv(bead, R, ke)
        var wob = 0.06 * Math.sin(k * Math.PI * 2) * (1 - k)
        var hx = hang.x + axis.x * 3 * ke, hy = hang.y + axis.y * 3 * ke
        b.a = 0.92 + 0.08 * ke
        // (the frame turns from the screen's axis to the fall's while it lets go)
        var rot = ease(sub(p, 0.2, 0.3))
        var fx = mixv(axis.x, dir.x, rot), fy = mixv(axis.y, dir.y, rot), fl = Math.max(1e-3, Math.hypot(fx, fy))
        b.fx = fx / fl; b.fy = fy / fl
        if (p < tLetGo) {
            b.x = hx; b.y = hy; b.r = r
            b.along = r * (1 + 0.32 * ke + wob); b.across = r * (1 - 0.08 * ke - wob)
            b.corner = r; b.tail = 0.45 * ke
            return b
        }
        // the fall: from rest under gravity (thrown up: fast off the module, slowing to the impact)
        var t = sub(p, tLetGo, tImpact)
        var f = thrown ? 1 - (1 - t) * (1 - t) : t * t
        b.x = mixv(hx, impact.x, f); b.y = mixv(hy, impact.y, f)
        var v = thrown ? 1 - t : t
        var st = 1 + 0.7 * v * Math.min(1, fall / 160)
        var hit = sub(p, tImpact, tFlat)
        b.r = R
        b.along = R * st * (1 - 0.5 * hit); b.across = R / Math.sqrt(st) * (1 + 0.6 * hit)
        b.corner = Math.min(b.along, b.across)
        b.tail = (0.45 * (1 - t) + 0.7 * (st - 1)) * (1 - hit)
        b.a = 1 - hit
        return b
    }
    // The ripple: the front's radius and the crests' height (0 flat … 1).
    readonly property real wave: sub(p, tImpact, 1)
    readonly property real front: p < tImpact ? 0 : bead * 0.8 + (reach - bead * 0.8) * (1 - Math.pow(1 - wave, 2.2))
    readonly property real amp: p < tImpact ? 0 : Math.pow(1 - wave, 1.4) * Math.min(1, 0.35 + wave * 6)

    // The pass covers the card and the bead's path (the bead starts outside the card, on its module).
    readonly property real pad: bead * 3
    readonly property rect box: {
        var x0 = Math.min(0, from.x - pad), y0 = Math.min(0, from.y - pad)
        var x1 = Math.max(area.width, from.x + from.width + pad), y1 = Math.max(area.height, from.y + from.height + pad)
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
        u0: Qt.vector4d(drop.drip.fx, drop.drip.fy, drop.impact.x, drop.impact.y)
        u1: Qt.vector4d(drop.drip.x, drop.drip.y, drop.drip.r, 1)
        u2: Qt.vector4d(drop.drip.a, drop.wavelength, drop.front, drop.ringPx)
        u3: Qt.vector4d(drop.amp, 10 * drop.refraction, drop.box.x, drop.box.y)
        property vector4d u4: Qt.vector4d(drop.drip.along, drop.drip.across, drop.drip.corner, drop.drip.tail)
    }
}
