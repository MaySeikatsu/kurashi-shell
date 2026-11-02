import QtQuick
import ".."

// liquid (W59.5 draft, W59.9a; K83, docs/ux/motion-engine.md §5 — the user's "fluidly growing out and morphing from the
// clicked shape to the new shape"; glass): the pressed module's own rect and radius (the origin: the pill, or the widget's
// box from IslandGeom, I340) flow into the card. Width leads — the body spreads along the bar first, as a drop does when
// it meets a surface — and height lags behind it, so the shape is a wide, shallow lens before it is a card; the corners go
// from the origin's radius to the card's with the tint. The neck (the join's fillets: a smooth-min union of the body and
// the bar or the module's block) stretches while the body pulls away and settles back as it lands; D2: it stays joined.
// The content cross-fades in once the body is most of the way (out first on a close). On a spring curve the width and
// the foot overshoot a little and settle (the meta allows it). A retarget morphs from where the shape is.
// At p = 1 every output is the card's own and `neck` is 1: the rest frame is the motion-off frame.
ShapeForm {
    // How far the neck stretches (param `neck`, 0–1; the liquid pack's 0.5).
    readonly property real neckParam: params && params.neck !== undefined ? Math.max(0, Math.min(1, params.neck)) : 0.5
    // The width's lead (fast out of the origin) and the height's lag (slow to leave it); past 1 both follow an overshooting
    // curve, so the bulge is the curve's.
    readonly property real lead: progress > 1 ? progress : 1 - Math.pow(1 - pc, 2.2)
    readonly property real lag: progress > 1 ? progress : Math.pow(pc, 1.6)
    cx: lerp(fromCx, toCx, lead)
    w: lerp(fromW, toW, lead)
    foot: lerp(fromFoot, toFoot, lag)
    grow: lag
    tint: smooth(0.05, 0.55, pc)
    content: smooth(0.45, 0.95, pc)
    // The neck's stretch over p (MorphShape's `stretch`, × its fillets): 1 at both ends, swelling while the body pulls
    // away (most at p ≈ 0.4) — the thread of a drop leaving its source — and easing back as it lands.
    neck: 1 + 1.4 * neckParam * Math.pow(Math.sin(Math.PI * Math.pow(pc, 0.8)), 2)
}
