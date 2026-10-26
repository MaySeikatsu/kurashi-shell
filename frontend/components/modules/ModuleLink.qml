import QtQuick

// What the modules of one host share (a bar, or an edge module group): the workspace chips a window is dragged onto (the
// window list asks which chip lies under a point, the chips ring the one it is over) and whether any of them is busy (a
// menu or a drag open: a hover-revealed host stays out). Plain state, no timers (Ma).
QtObject {
    id: link
    property bool vertical: false
    // The workspace chip a window is dragged over, -1 while nothing is dragged.
    property int dragWs: -1
    // The chips' delegates, set by the workspaces module ([] while there is none).
    property var chips: []
    // { "<key>": true } — modules that hold the host open.
    property var holds: ({})
    readonly property bool busy: Object.keys(holds).length > 0
    function hold(key, on) {
        if (!!holds[key] === on) return
        var n = Object.assign({}, holds)
        if (on) n[key] = true
        else delete n[key]
        holds = n
    }

    // The chip under a scene point (half the spacing on each side) across the host's whole thickness, so a thin dot is
    // still a target; null when none.
    function pillAt(sx, sy, slack) {
        for (var i = 0; i < chips.length; i++) {
            var it = chips[i]
            if (!it || !it.modelData) continue
            var p = it.mapToItem(null, 0, 0)
            var hit = vertical ? (sy >= p.y - slack && sy < p.y + it.height + slack)
                : (sx >= p.x - slack && sx < p.x + it.width + slack)
            if (hit) return it.modelData
        }
        return null
    }
    function boxes() {
        var out = []
        for (var i = 0; i < chips.length; i++) {
            var it = chips[i]
            if (!it || !it.modelData) continue
            var p = it.mapToItem(null, 0, 0)
            out.push({ id: it.modelData.id, x: Math.round(p.x), y: Math.round(p.y), w: Math.round(it.width), h: Math.round(it.height) })
        }
        return out
    }
}
