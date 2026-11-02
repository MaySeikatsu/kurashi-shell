import QtQuick
import ".."

// liquid (W59.5, K83; docs/ux/motion-engine.md §5 — the user's "fluidly growing out and morphing from the clicked shape";
// glass): the pressed module's own rect and radius (the origin: IslandGeom's box, I340) flow into the card. Width leads
// — the body spreads along the bar first, as a drop does when it meets a surface — and height lags behind it, so the
// shape is a wide, shallow lens before it is a card; the corners go from the module's radius to the card's with the tint.
// The content cross-fades in once the body is most of the way (out first on a close). On a spring curve the width and
// the foot overshoot a little and settle (the meta allows it). A retarget morphs from where the shape is.
// The neck — the smooth-min union between the body and the module that stretches and necks off once the card stands
// free, or stays joined (D2) — is MorphShape's (W59.3 owns it): `neck` here is its strength over p (param `neck` 0–1).
// DRAFT (W59.5): written against W59.3's ShapeForm; `liquid` stays unavailable until it is seen on niri.
ShapeForm {
    readonly property real neckParam: params && params.neck !== undefined ? Math.max(0, Math.min(1, params.neck)) : 0.5
    // The width's lead and the height's lag (past 1 they follow an overshooting curve).
    readonly property real lead: progress > 1 ? progress : smooth(0, 0.7, pc)
    readonly property real lag: progress > 1 ? progress : smooth(0.15, 1, pc)
    cx: lerp(fromCx, toCx, lead)
    w: Math.max(fromW, lerp(fromW, toW, lead))
    foot: lerp(fromFoot, toFoot, lag)
    grow: lag
    tint: smooth(0.1, 0.6, pc)
    content: smooth(0.45, 0.95, pc)
    // The neck's strength: full while the body leaves the module, thinning as it stands free; stays at `neck` with D2's
    // joined hinge (a param of 1 keeps it joined).
    readonly property real neck: neckParam >= 1 ? 1 : neckParam * (1 - smooth(0.55, 0.9, pc))
}
