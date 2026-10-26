import QtQuick
import "../../core"

// Keeps a hover-revealed surface out while the pointer still rests on its screen edge (W44). EdgeReveal lets its strip go
// once the surface is out, so the surface's own window holds the pointer — but a pointer that does not move gets no
// enter on a window mapped under it (sway, measured), so the surface would hide 400 ms later and the strip, back under
// the resting pointer, would reveal it again: a loop. While `claim` (the surface reveals on hover) this claims the same
// shared strip (EdgeStrips) under its own key — so the strip stays mapped across the reveal, under the pointer — and,
// while `active` (the surface is out), says whether the pointer is on it inside [from, to]; the surface leaves its
// outermost pixels out of its input region so the strip keeps the pointer there. Plain state, no timers (Ma).
QtObject {
    id: h
    property string output: ""
    property string edge: ""
    property string key: ""
    property bool claim: false
    property bool active: false
    property real from: 0
    property real to: -1
    readonly property real p: EdgeStrips.posOf(output, edge)
    readonly property bool held: active && p >= 0 && p >= from && (to < 0 || p <= to)

    property string claimed: ""
    function sync() {
        var want = claim && output !== "" && edge !== "" && key !== "" ? output + "/" + edge + "/" + key : ""
        if (want === claimed) return
        if (claimed !== "") { var c = claimed.split("/"); EdgeStrips.release(c[0], c[1], c.slice(2).join("/")) }
        claimed = want
        if (want !== "") EdgeStrips.claim(output, edge, key)
    }
    onClaimChanged: sync()
    onOutputChanged: sync()
    onEdgeChanged: sync()
    onKeyChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: { claim = false; sync() }
}
