import QtQuick
import "../../../core"

// TextBox (W53.5, docs/ux/styles.md §7): the island as a 16-bit RPG text box — a window with the look's stepped corner
// (the frame draws its border) and, once the line has typed itself out, the box's "more" mark: a small downward triangle
// in whole grid pixels at its lower right. Static (nothing blinks: Ma).
IslandBase {
    id: tb
    readonly property int g: Math.max(1, Theme.grid(Screen.height))
    radius: Theme.rLg
    // The mark stands in the box's end padding: 3 grid pixels over 1, two grid pixels in from the border.
    Column {
        visible: !tb.typing && !tb.vertical
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 3 * tb.g; bottomMargin: 3 * tb.g }
        Repeater {
            model: 2
            Rectangle {
                required property int index
                x: index * tb.g
                width: (3 - 2 * index) * tb.g
                height: tb.g
                antialiasing: false
                color: Theme.fg
            }
        }
    }
}
