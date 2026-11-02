import QtQuick
import "../../../core"

// glitch (W59.8b, K83; docs/ux/motion-engine.md §5 — the YoRHa tear): the card arrives in slices. Eight horizontal slices of
// uneven height, each sliding sideways by ±(1 − p)·24 px (rolled per slice, some stay put), with an RGB split of ≤ 3 px that
// goes with them, and two scanline tears that jump further. The rolls change six times over the transition, each smaller
// than the last, so the card stutters into place and is itself at p = 1. Crisp: the offsets are whole device px. Never a
// strobe: no slice changes its brightness, and the card fades in over the first tenth of an open and out over the last tenth of
// a close (brief §11: the meta flags it `flash`, and the harness checks the sweep). Closing runs the same frames backwards
// (p is the only input).
// The pass (glitch.frag) covers the card and the margin its slices reach into. Params: none.
SheetForm {
    id: glitch

    // px (logical): the slices' reach at p = 0, the RGB split, the tears' reach and height.
    readonly property real reach: 24
    readonly property real split: 3
    readonly property real tearReach: 14
    readonly property real tearH: 2
    readonly property real margin: reach + split + 1
    readonly property real fade: Math.min(1, p / 0.1)

    SheetForm.Pass {
        host: glitch
        name: "glitch"
        x: glitch.area.x - glitch.margin
        width: glitch.area.width + 2 * glitch.margin
        u0: Qt.vector4d(glitch.margin, glitch.reach, glitch.split, glitch.tearReach)
        u1: Qt.vector4d(8, 0.27, 0.71, glitch.tearH)
        u2: Qt.vector4d(Math.max(1, glitch.capture.textureSize.width), Math.max(1, glitch.capture.textureSize.height),
            6, glitch.fade)
    }
}
