import QtQuick
import ".."

// expand (K83, brief §5; the user's "simple panel expand"): the card stands at its full width from the first frame and is
// revealed from the bar's edge — its foot runs from the origin's line to the card's, the content still where it rests and
// cut by the edge as it comes (a window shade, not a growth out of the widget). No overshoot: a shade does not bounce.
// On the island the body comes out from under the pill as the pill's tint gives way to the card's.
ShapeForm {
    grow: pc
    tint: pc
    foot: lerp(fromFoot, toFoot, pc)
}
