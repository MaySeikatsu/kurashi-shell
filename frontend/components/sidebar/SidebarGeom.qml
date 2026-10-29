pragma Singleton
import QtQuick
import Quickshell
import "../../core"

// Where an open sidebar joins its bars (W34; row 521): per output, side and bar edge, the span of that bar's edge the
// column covers at rest, so a bar that rules its edge (line chrome) can leave its rule out there and bar and column read
// as one sheet — the column's outline runs round its fillet into the rule's end (ColumnShape, `ruled`). Both sidebars may
// be out at once, and a column that joins a top and a bottom bar meets two rules: one opening per side and bar edge.
// Published by Sidebar.qml only while the column stands at rest under (or beside) a ruled bar; withdrawn the moment it
// starts to fold. Plain state (Ma).
Singleton {
    // { "<output>": { "<side>/<edge>": { side, edge, from, to } } }: the bar's edge ("top", "bottom", "left", "right") and the
    // span along it, in px from the output's start on that edge (its left end, or its top end for a side edge).
    property var openings: ({})
    // I301: which sidebars are out (pinned, toggled or out on hover), per output. A sidebar that keeps space only while it
    // is out (`reserve = on` with `hover`: runtime.layout `sidebars.<side>.reserve_open`) has that zone held by whoever
    // holds its edge's zone (frame, bar, dock, edge group), or by its own window where nothing does.
    property var outs: ({})
    function setOut(output, side, on) {
        if (output === "" || side === "" || (!!(outs[output] || {})[side]) === !!on) return
        var n = Object.assign({}, outs)
        n[output] = Object.assign({}, outs[output] || {})
        n[output][side] = !!on
        outs = n
    }
    // The zone an edge's holder keeps for its sidebar while it is out (0 while it is in, and for top and bottom).
    function openZone(output, edge) {
        if ((edge !== "left" && edge !== "right") || !(outs[output] || {})[edge]) return 0
        var s = (ShellLayout.of(output).sidebars || {})[edge]
        return s ? Math.max(0, Math.round(s.reserve_open || 0)) : 0
    }
    function set(output, side, edge, from, to) {
        if (output === "" || side === "" || edge === "") return
        var k = side + "/" + edge, o = (openings[output] || {})[k]
        if (o && o.from === from && o.to === to) return
        var n = Object.assign({}, openings)
        n[output] = Object.assign({}, openings[output] || {})
        n[output][k] = { side: side, edge: edge, from: from, to: to }
        openings = n
    }
    // Withdraws `side`'s opening on `edge`, or every opening of `side` when `edge` is absent.
    function clear(output, side, edge) {
        var cur = openings[output]
        if (!cur) return
        var m = Object.assign({}, cur), changed = false
        for (var k in cur) {
            var o = cur[k]
            if (o.side === side && (edge === undefined || edge === "" || o.edge === edge)) { delete m[k]; changed = true }
        }
        if (!changed) return
        var n = Object.assign({}, openings)
        if (Object.keys(m).length === 0) delete n[output]
        else n[output] = m
        openings = n
    }
    // Every opening on `output`: [{ side, edge, from, to }].
    function openingsOf(output) {
        var cur = openings[output] || {}, out = []
        for (var k in cur) out.push(cur[k])
        return out
    }
    // K71: the openings on one bar edge, along the output's edge, read from the bar's own start — a floating bar stands
    // `band + gap` in from the output's ends (its `start`), a docked one at 0, where the two agree. [{ side, from, to }].
    function openingsIn(output, edge, start) {
        return openingsOf(output).filter(function (o) { return o.edge === edge }).map(function (o) {
            return { side: o.side, from: o.from - start, to: o.to - start }
        })
    }
}
