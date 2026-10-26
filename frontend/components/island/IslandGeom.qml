pragma Singleton
import QtQuick
import Quickshell

// Where each output's island pill rests, and which output's pill the Stage has taken (W21 morph). The Islands report
// their pill (`report`, only on a change); the Stage reads it to start its one shape at the pill's exact rect and to fold
// back into it, and names the output while its shape is out (`takenOn`), so that output's bar hides its pill: one
// island on screen, never two. Plain state, no timers (Ma).
// W34 (docs/ux/motion.md): also the registry of the bar's other origins — every widget a Stage panel grows out of (the
// quick button, the tray icons, the sidebar buttons, mod widgets) registers itself here per output under a key
// (`quick`, `tray:<item>`, `sidebar:<side>`, `mod:<mod>:<widget>`; AnchorReport does it). Nothing is reported per frame:
// the item is kept and its box read only when a surface asks (`rectOf`), so an idle bar costs nothing.
Singleton {
    // { "<output>": { w, h, dx, face } }: the pill's width and face height (without the keycap shadow), the offset of its
    // centre from the bar's centre (the secondary glyph and "+N" beside it push it left), and the face it shows.
    property var pills: ({})
    function report(output, w, h, dx, face) {
        if (output === "") return
        var p = pills[output]
        if (p && p.w === w && p.h === h && p.dx === dx && p.face === face) return
        var n = Object.assign({}, pills)
        n[output] = { w: w, h: h, dx: dx, face: face }
        pills = n
    }
    // The pill as the Stage starts from it: its size and face, and its centre's offset from the output's centre — the bar
    // centres the island by default (`dx` alone); a zone that puts it elsewhere adds where its module stands (`place`, read
    // now, never reported per frame). `inset`: how far its bar stands from its edge (a floating bar's band + gap, K71).
    function pillOf(output) {
        var p = pills[output]
        if (!p) return null
        var pl = places[output]
        var b = pl ? barOf(output, pl.edge) : null
        // The module's centre, from the item itself in the bar window that holds it (its place on the output counted, as
        // rectOf); the module's own `where()` while no bar of this output is known to hold it.
        var off = 0
        var it = pl ? pl.by : null, hb = it && it.mapToItem ? barHolding(output, it) : null
        if (hb && hb.sw > 0 && it.width > 0) off = hb.ox + it.mapToItem(null, it.width / 2, 0).x - hb.sw / 2
        else if (pl) off = pl.where()
        return { w: p.w, h: p.h, dx: p.dx + off, face: p.face, edge: pl ? pl.edge : "top", inset: b ? b.inset : 0 }
    }
    // ---- where the island's module stands (K72: any zone of any bar). `places["<output>"] = { edge, where, by }`: `where()`
    // gives the module's centre from the output's centre, px (0 for a centred island on a full-width bar).
    property var places: ({})
    function place(output, edge, where, by) {
        if (output === "" || !where) return
        var n = Object.assign({}, places)
        n[output] = { edge: edge, where: where, by: by }
        places = n
    }
    function unplace(output, by) {
        var o = places[output]
        if (!o || o.by !== by) return
        var n = Object.assign({}, places)
        delete n[output]
        places = n
    }
    // ---- the bars of each output (K71: one per edge). `bars["<output>/<edge>"] = { edge, inset, size, floating, mapped, root,
    // ox, oy, sw }`: how far the bar's body stands from its edge (a floating bar's band + gap), its thickness, whether it
    // floats, whether its window is on screen, the window's content item, its top-left corner on the output and the output's
    // width — the Stage's morph
    // and the neck follow a floating bar's inset; the frame waits for a bar that carries its strip (row 492 b) before it maps
    // its side strips, a pinned sidebar for the horizontal bars that hold a zone; `rectOf` tells an origin's bar by `root`.
    property var bars: ({})
    function setBar(output, edge, info) {
        if (output === "") return
        var k = output + "/" + edge, o = bars[k]
        if (o && info && o.inset === info.inset && o.size === info.size && o.floating === info.floating && o.mapped === info.mapped
                && o.root === (info.root || null) && o.ox === (info.ox || 0) && o.oy === (info.oy || 0) && o.sw === (info.sw || 0)) return
        if (!o && !info) return
        var n = Object.assign({}, bars)
        if (info) n[k] = { edge: edge, inset: info.inset, size: info.size, floating: info.floating, mapped: info.mapped,
                           root: info.root || null, ox: info.ox || 0, oy: info.oy || 0, sw: info.sw || 0 }
        else delete n[k]
        bars = n
    }
    function barOf(output, edge) { return bars[output + "/" + edge] || null }
    // The bar of `output` whose window holds `item` (null: none of its bars). Walked only when a surface asks.
    function barHolding(output, item) {
        var mine = []
        for (var k in bars) if (k.indexOf(output + "/") === 0 && bars[k].root) mine.push(bars[k])
        for (var p = item; p && mine.length > 0; p = p.parent)
            for (var i = 0; i < mine.length; i++) if (mine[i].root === p) return mine[i]
        return null
    }
    // The output whose pill is inside the Stage's shape right now; "" when none.
    property string takenOn: ""
    // Where the shape opens the `takenOn` bar's rule (line chrome, W30): from the bar's centre, left and right, in px;
    // 0, 0 while the shape is not out on a ruled strip. The bar leaves its rule out in between (the shape draws the rule
    // there, and the join).
    property real openL: 0
    property real openR: 0
    function setOpening(l, r) {
        if (openL !== l) openL = l
        if (openR !== r) openR = r
    }

    // ---- origins (W34). `origins["<output>"]["<key>"] = { item, by }`: the registered item and who registered it. Bumps
    // `revision` on every (un)registration, so a binding that calls rectOf() re-reads.
    property var origins: ({})
    property int revision: 0
    function register(output, key, item, by) {
        if (output === "" || key === "" || !item) return
        var o = origins[output] || ({})
        if (o[key] && o[key].item === item && o[key].by === by) return
        o[key] = { item: item, by: by }
        origins[output] = o
        revision++
    }
    function unregister(output, key, by) {
        var o = origins[output]
        if (!o || !o[key] || o[key].by !== by) return
        delete o[key]
        revision++
    }
    // The registered item's box on its output (logical px, its bar window's place counted: row 512 — a floating bar's window
    // stands in from the output's corner) as { x, y, w, h, edge }, `edge` the bar it stands in ("" when none of this output's
    // bars holds it), or null: no such key, or the item is gone or hidden. `key` ending in ":" takes the first registered key
    // with that prefix (a mod's panel opened from another of its widgets).
    function rectOf(output, key) {
        var o = origins[output]
        if (!o) return null
        var a = o[key]
        if (!a && key.charAt(key.length - 1) === ":") {
            for (var k in o) if (k.indexOf(key) === 0 && o[k].item && o[k].item.visible) { a = o[k]; break }
        }
        if (!a || !a.item || !a.item.visible || a.item.width <= 0) return null
        var t = a.item
        var p0 = t.mapToItem(null, 0, 0), p1 = t.mapToItem(null, t.width, t.height)
        var b = barHolding(output, t)
        return { x: (b ? b.ox : 0) + Math.min(p0.x, p1.x), y: (b ? b.oy : 0) + Math.min(p0.y, p1.y),
                 w: Math.abs(p1.x - p0.x), h: Math.abs(p1.y - p0.y), edge: b ? b.edge : "" }
    }
}
