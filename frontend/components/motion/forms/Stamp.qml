import QtQuick
import ".."

// stamp (K83, brief §5; a hanko): the card comes down onto the screen. It appears a little above it — 1.06× about the
// bar's edge, its elevation one level higher and softer — and falls, accelerating, onto its place (p = 0.55), where it
// presses: a short squash, wider and lower, as the ink takes, then it stands. Closing lifts it off the same way. It fades
// in over the first 30 % of the fall; content and card move as one (no cut). An overshooting curve presses harder.
ShapeForm {
    readonly property real contact: 0.55
    // The fall: 1.06 → 1, accelerating (a weight, not a spring).
    readonly property real fall: clamp01(pc / contact)
    readonly property real s: 1 + 0.06 * (1 - fall * fall)
    // The press: one squash after contact (sin over the rest of the travel, easing out), deeper past 1.
    readonly property real t: clamp01((pc - contact) / (1 - contact))
    readonly property real q: 0.032 * Math.sin(Math.PI * t) * (1 - 0.35 * t) + Math.max(0, progress - 1) * 0.3
    sx: s * (1 + 0.55 * q)
    sy: s * (1 - q)
    masked: moving
    below: smooth(0, 0.3, pc)
    content: 1
    clipsContent: false
    lift: 1 - smooth(0.12, contact, pc)
}
