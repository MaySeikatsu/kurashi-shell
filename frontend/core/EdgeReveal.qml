import QtQuick
import Quickshell

// One hover reveal at a screen edge (K71; the dock's I137 rules, now everyone's; row 524: the one reveal model of the bars,
// the dock and the sidebars): while `enabled`, claims its output's edge strip (EdgeStrips) and sets `revealed` once the
// pointer has rested `ShellLayout.revealDelay` ms on the strip inside [from, to] (twice as long on an edge another output
// touches: the pointer crosses it on its way there). It stays revealed while the pointer is on the strip inside the span
// or the consumer says the pointer is on it (`holdIn`: its window, its menus, its keyboard focus), and goes 400 ms after
// the pointer has left both. `to < 0` means the whole edge.
// The strip stays claimed while the surface is out: a pointer that rests on the edge (no motion) gets no `enter` on a
// window mapped under it (sway, measured), so a strip given up at the reveal would hide the surface 400 ms later and,
// mapped again under the pointer, reveal it again — a loop. The strip lies under the surface (mapped first), so a revealed
// surface leaves its outermost `cut` px (the strip's input, 2 px) out of its input region, and the strip keeps reporting
// the pointer there. No timer runs while nothing moves (Ma).
QtObject {
    id: r
    required property var screen          // the ShellScreen
    required property string edge         // top | bottom | left | right
    property string key: ""               // the consumer's id on this strip (unique per output and edge)
    property bool enabled: true
    property real from: 0
    property real to: -1
    property bool holdIn: false
    property bool revealed: false

    // The strip's input depth at the screen edge (EdgeStripHost): what a revealed surface leaves to the strip.
    readonly property int stripPx: 2
    // How many px the consumer leaves out of its input region on its screen edge, its body standing `inset` px from it.
    function cutFor(inset) { return enabled && revealed ? Math.max(0, stripPx - Math.max(0, Math.round(inset))) : 0 }

    readonly property string output: screen ? screen.name : ""
    readonly property real p: EdgeStrips.posOf(output, edge)
    readonly property bool onSpan: enabled && p >= 0 && p >= from && (to < 0 || p <= to)
    readonly property bool pointerIn: onSpan || (revealed && holdIn)

    readonly property bool sharedEdge: {
        var s = screen
        if (!s) return false
        var all = Quickshell.screens
        for (var i = 0; i < all.length; i++) {
            var o = all[i]
            if (!o || o.name === s.name) continue
            var overlapX = o.x < s.x + s.width && o.x + o.width > s.x
            var overlapY = o.y < s.y + s.height && o.y + o.height > s.y
            if (edge === "top" && overlapX && o.y + o.height === s.y) return true
            if (edge === "bottom" && overlapX && o.y === s.y + s.height) return true
            if (edge === "left" && overlapY && o.x + o.width === s.x) return true
            if (edge === "right" && overlapY && o.x === s.x + s.width) return true
        }
        return false
    }
    readonly property int delayMs: ShellLayout.revealDelay * (sharedEdge ? 2 : 1)

    property Timer revealTimer: Timer { interval: Math.max(1, r.delayMs); onTriggered: if (r.onSpan) r.revealed = true }
    property Timer hideTimer: Timer { interval: 400; onTriggered: if (!r.pointerIn) r.revealed = false }

    onOnSpanChanged: if (onSpan && !revealed) { if (delayMs <= 0) revealed = true; else revealTimer.restart() }
    onPointerInChanged: {
        if (pointerIn) hideTimer.stop()
        else { revealTimer.stop(); if (revealed) hideTimer.restart() }
    }
    onEnabledChanged: { sync(); if (!enabled) { revealTimer.stop(); hideTimer.stop(); revealed = false } }
    onOutputChanged: sync()
    onEdgeChanged: sync()
    onKeyChanged: sync()
    // The strip this reveal holds ("" while none), so a change of output, edge or key releases the old one.
    property string held: ""
    function sync() {
        var want = enabled && output !== "" && key !== "" ? output + "/" + edge + "/" + key : ""
        if (want === held) return
        if (held !== "") { var h = held.split("/"); EdgeStrips.release(h[0], h[1], h.slice(2).join("/")) }
        held = want
        if (want !== "") EdgeStrips.claim(output, edge, key)
    }
    Component.onCompleted: sync()
    Component.onDestruction: { enabled = false }
}
