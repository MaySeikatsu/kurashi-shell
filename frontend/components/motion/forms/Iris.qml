import QtQuick
import ".."

// iris (K83, brief §5; Material's circular reveal): the card at rest, seen through a circle that opens from where the user
// pressed (W59.9a, row 658: the module's press point, `atX`/`atY`), else from the origin's centre where it meets the line
// the card hangs from; its radius from 0 to the card's farthest corner and its shadow. The join's fillets appear as the
// circle crosses the bar's edge; the bar's strip and the island's head stay whole. The pill's own tint gives way to the
// card's over the first 40 %, while the circle is still small, so a strip's melted head does not blink.
ShapeForm {
    readonly property real reach: {
        var dx = Math.max(Math.abs(toCx - toW / 2 - atX), Math.abs(toCx + toW / 2 - atX))
        var dy = Math.max(Math.abs(toFoot - atY), Math.abs(atY - Math.min(toTop, edgeY)))
        // (past the card's corner by its elevation's reach, so the shadow is not cut at rest-1)
        return Math.sqrt(dx * dx + dy * dy) + 48
    }
    tint: smooth(0, 0.4, pc)
    masked: moving
    irisX: atX
    irisY: atY
    irisR: reach * pc
}
