import QtQuick
import ".."

// outline (K83, brief §5; Windows 95's zoom rectangle): while it moves nothing of the card is drawn but an outline that
// steps from the origin's box to the card's in `frames` (6–8) held steps, the step before it still faintly there (the
// redraw's afterimage); at p = 1 the card is there at once. Closing: the card goes at once and the outline steps home.
// The bar keeps its strip and the island its head (the pill's look) until the card stands.
ShapeForm {
    readonly property int frames: Math.max(3, Math.min(12, Math.round(params && params.frames > 0 ? params.frames : 7)))
    readonly property int step: Math.min(frames - 1, Math.floor(pc * frames))
    function rectAt(k) {
        var f = (k + 1) / (frames + 1)
        var x0 = lerp(fromCx - fromW / 2, toCx - toW / 2, f), x1 = lerp(fromCx + fromW / 2, toCx + toW / 2, f)
        var y0 = lerp(fromTop, toTop, f), y1 = lerp(fromFoot, toFoot, f)
        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0), r: lerp(fromR, toR, f) }
    }
    outline: moving
    masked: moving
    below: moving ? 0 : 1
    tint: moving ? 0 : 1
    content: moving ? 0 : 1
    rects: {
        if (!moving || progress <= 0) return []
        var cur = rectAt(step)
        cur.a = 1
        if (step === 0) return [cur]
        var prev = rectAt(step - 1)
        prev.a = 0.35
        return [prev, cur]
    }
}
