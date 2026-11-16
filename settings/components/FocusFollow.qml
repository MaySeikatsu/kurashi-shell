import QtQuick
import "../core"

// The keyboard focus stays in view (W94): when a control inside the view takes the focus, the view scrolls the least that
// shows it, a pad's room around it. Place it inside the Flickable it drives, as KineticWheel: `FocusFollow { view: p }`;
// `reveal(item)` is also there for an item that is not focused (a preview opened, a result that appeared).
Item {
    id: ff
    property Flickable view: null

    function reveal(item) {
        var v = ff.view
        if (!v || !item) return
        var top = item.mapToItem(v.contentItem, 0, 0).y
        var bottom = top + item.height
        if (top < v.contentY) v.contentY = Math.max(0, top - Theme.pad)
        else if (bottom > v.contentY + v.height) v.contentY = Math.min(bottom - v.height + Theme.pad, v.contentHeight - v.height)
    }
    Connections {
        target: ff.view ? ff.view.Window.window : null
        function onActiveFocusItemChanged() {
            var w = ff.view.Window.window
            var f = w ? w.activeFocusItem : null
            for (var it = f; it; it = it.parent) if (it === ff.view) { ff.reveal(f); return }
        }
    }
}
