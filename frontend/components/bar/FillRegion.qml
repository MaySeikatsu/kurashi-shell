import QtQuick
import Quickshell

// A blur region that stays on an item as it moves in its window. `Region { item: … }` takes the item's place once and does
// not follow it (a strip whose room grows with the shadow's strength moved its fills and left the blur behind, a band's
// width of blurred backdrop standing in the hole). The rect is bound here, so it goes where the item goes.
Region {
    property Item of: null
    readonly property point at: {
        if (!of) return Qt.point(0, 0)
        // (read so the binding runs when the item or what holds it moves; mapToItem alone notifies nothing)
        var moved = of.x + of.y + (of.parent ? of.parent.x + of.parent.y : 0)
        return of.mapToItem(null, 0, 0)
    }
    x: at.x
    y: at.y
    width: of ? of.width : 0
    height: of ? of.height : 0
}
