pragma Singleton
import QtQml
import QtQuick
import Quickshell

// Layout moves (I472/I478, session 28, docs/ux/transitions.md "Layout"): a bar that changes its edge does not pop out
// here and in there. A layer surface cannot change its edge and keep its picture, so the old bar goes and the new one
// comes — this notices the move (an output whose layout lost a bar on one edge and gained one on another in the same
// change), and a traveller (surfaces/Traveller.qml) carries the bar's body along the screen from the old place to the
// new one while the new bar waits unseen (`hides`), then hands over. `theme.motion.layout_move` picks the way (token
// `motion.layout_move`): follow the screen's sides, part in the middle and run down both sides, drip, fade; off, and
// with motion off, it is the cut it always was. Nothing here runs or is made at rest (Ma).
Singleton {
    id: tr
    readonly property var doc: Store.docs ? Store.docs["runtime.layout"] : undefined
    readonly property string style: Theme.springOn ? String(Theme.tok("motion.layout_move", "follow")) : "off"
    // output -> the edges that have a bar ("top,left"), as of the last layout; output -> the move under way.
    property var before: ({})
    property var moves: ({})
    property int serial: 0
    function barsOf(name) {
        var out = []
        if (!doc) return ""
        var e = ["top", "right", "bottom", "left"]
        for (var i = 0; i < e.length; i++) if (ShellLayout.edgeOf(name, e[i]).bar === true) out.push(e[i])
        return out.join(",")
    }
    onDocChanged: {
        if (!doc) return
        var s = Quickshell.screens, next = ({}), mv = null
        for (var i = 0; i < s.length; i++) {
            var name = s[i].name, now = barsOf(name), was = before[name]
            next[name] = now
            if (was === undefined || was === now || style === "off") continue
            var a = was.split(","), b = now.split(",")
            var gone = a.filter(function (x) { return x !== "" && b.indexOf(x) < 0 })
            var come = b.filter(function (x) { return x !== "" && a.indexOf(x) < 0 })
            if (gone.length !== 1 || come.length !== 1) continue
            if (mv === null) { mv = ({}); for (var k in moves) mv[k] = moves[k] }
            var size = ShellLayout.edgeOf(name, come[0]).size
            mv[name] = { from: gone[0], to: come[0], n: ++serial, size: size > 0 ? size : Theme.barH }
        }
        before = next
        if (mv !== null) moves = mv
    }
    // (made when the first bar asks: what stands now is where the next change starts from)
    Component.onCompleted: {
        if (!doc) return
        var s = Quickshell.screens, now = ({})
        for (var i = 0; i < s.length; i++) now[s[i].name] = barsOf(s[i].name)
        before = now
    }
    // The bar on this edge of this output is on its way: it stays unseen until the traveller has brought it.
    function hides(name, edge) { var m = moves[name]; return m !== undefined && m.to === edge }
    function done(name, n) {
        var m = moves[name]
        if (m === undefined || m.n !== n) return
        var mv = ({})
        for (var k in moves) if (k !== name) mv[k] = moves[k]
        moves = mv
    }
}
