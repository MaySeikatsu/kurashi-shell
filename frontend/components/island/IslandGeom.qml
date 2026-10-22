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
    function pillOf(output) { return pills[output] || null }
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
    // The registered item's box on its bar's window — the output's own px for a top or bottom bar, which spans the output
    // — as { x, y, w, h }, or null: no such key, or the item is gone or hidden. `key` ending in ":" takes the first
    // registered key with that prefix (a mod's panel opened from another of its widgets).
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
        return { x: Math.min(p0.x, p1.x), y: Math.min(p0.y, p1.y), w: Math.abs(p1.x - p0.x), h: Math.abs(p1.y - p0.y) }
    }
}
