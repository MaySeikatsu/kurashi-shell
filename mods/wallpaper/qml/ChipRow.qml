import QtQuick
import qs.core

// A row of the pickers' chips that the keyboard walks (W99): Left and Right move along it (to the chip before or after
// in the focus chain, within the row), Down goes to the grid. The targets, the folders, the breadcrumb and the sort are
// each one. `focusCurrent()` gives the focus to the chip marked `here` (or `selected`), else the first.
Flow {
    id: row
    property var host: null
    spacing: Theme.xs

    function inRow(it) {
        for (var p = it; p; p = p.parent) if (p === row) return true
        return false
    }
    function step(forward) {
        var w = row.Window.window
        var it = w ? w.activeFocusItem : null
        var next = it ? it.nextItemInFocusChain(forward) : null
        if (next && next !== it && inRow(next)) next.forceActiveFocus()
    }
    // The chips in order, depth first (a Repeater's delegates sit beside it).
    function chips() {
        var out = []
        var walk = function (it) {
            for (var i = 0; i < it.children.length; i++) {
                var c = it.children[i]
                if (c.visible && c.activeFocusOnTab) out.push(c)
                else walk(c)
            }
        }
        walk(row)
        return out
    }
    function focusCurrent() {
        var cs = chips()
        if (cs.length === 0) return false
        for (var i = 0; i < cs.length; i++) {
            if (cs[i].here === true || cs[i].selected === true) { cs[i].forceActiveFocus(); return true }
        }
        cs[0].forceActiveFocus()
        return true
    }
    Keys.onLeftPressed: step(false)
    Keys.onRightPressed: step(true)
    Keys.onDownPressed: event => {
        if (host && host.view && host.view.visible) host.focusGrid()
        else event.accepted = false
    }
}
