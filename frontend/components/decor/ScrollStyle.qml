import QtQuick
import "../../core"

// ScrollStyle (W53.0a, K80): a scroll bar in this look. A caller keeps its own width where the look leaves it
// (`width(own)`), adds arrow buttons with `arrows` (9x, XP), and draws the thumb as `thumb` says (pill = today's, flat,
// bevel, gel). A look naming a scroll part (`[slots] scroll`, contract `scroll/ScrollBase.qml`) draws the whole bar
// (track, thumb, arrows) instead: `part` is its url for a Loader in the ScrollBar's contentItem.
// (A QtObject, as MenuStyle and TooltipStyle: as an Item its `width(own)` was shadowed by Item.width.)
QtObject {
    readonly property string file: Theme.pascal(Theme.slot("scroll"))
    readonly property bool has: file !== ""
    readonly property bool arrows: Theme.decor("scroll.arrows", false) === true
    readonly property string thumb: Theme.decor("scroll.thumb", "pill")
    function width(own) { var v = Theme.decor("scroll.width", 0); return v > 0 ? v : own }
    readonly property url part: has ? Qt.resolvedUrl("scroll/" + file + ".qml") : ""
}
