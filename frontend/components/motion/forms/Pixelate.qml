import QtQuick
import "../../../core"

// pixelate (W59.8b, K83; docs/ux/motion-engine.md §5 — the mosaic, snes and ps2 or any pixel look): the card resolves from a
// coarse mosaic to sharp in held steps. Its blocks are 32, 16, 8, 4, 2, then 1 device px, one size per step of p (0 … 0.2 …
// 0.8, 0.95 … 1: the 2-px step is long enough to read, the 1-px one is the landing); each block takes the colour of the
// capture at its centre, and the mosaic fades in over the first step (the card's alpha ramps over the first 0.2 of p).
// Closing is the same function of p, so the card coarsens back and fades out. At a block of one device px the card is itself:
// the last step is the rest frame. One fragment pass over the capture (pixelate.frag). Params: none.
SheetForm {
    id: pix

    // The held step: 0 (blocks of 32 px) … 5 (1 px).
    readonly property int level: p < 0.2 ? 0 : p < 0.4 ? 1 : p < 0.6 ? 2 : p < 0.8 ? 3 : p < 0.95 ? 4 : 5
    readonly property real block: Math.pow(2, 5 - level)
    readonly property real fade: Math.min(1, p / 0.2)

    SheetForm.Pass {
        host: pix
        name: "pixelate"
        u0: Qt.vector4d(pix.block, pix.fade, Math.max(1, pix.capture.textureSize.width),
            Math.max(1, pix.capture.textureSize.height))
    }
}
