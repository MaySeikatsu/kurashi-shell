import QtQuick
import "../core"

// Fresh text on all text (session 30, I503, docs/ux/session-30.md §5; the user: the spawn "should get the option added to
// apply to ALL spawned text, not just mostly headlines/titles"): under `theme.typography.fx.scope = all`, a surface that
// opens has every plain label it shows written in by the spawn, not only the labels that carry a TextFx of their own.
// Put one in a surface: `TextSpawnAll { root: content; shown: <the surface opens> }`. On each opening it walks the visible
// items under `root` once and starts each Text's spawn — a Text without a TextFx gets one, made once and kept (a kept
// surface is shown again with its labels written in anew). Ma: with the scope on headings or no spawn, nothing is walked
// or made; a spawn is one short animation per label.
Item {
    id: tsa
    property Item root: null
    property bool shown: false
    readonly property bool on: Theme.textScope === "all" && Theme.textSpawn !== "none"
    width: 0
    height: 0
    visible: false
    onShownChanged: if (shown && on) Qt.callLater(walk)
    Component { id: fxC; TextFx {} }
    function isText(it) {
        return it.truncated !== undefined && it.maximumLineCount !== undefined && it.textFormat !== undefined && it.text !== undefined
    }
    function fxOf(t) {
        var c = t.children
        for (var i = 0; i < c.length; i++) if (c[i].objectName === "textfx") return c[i]
        return null
    }
    function walk() {
        if (!root || !on) return
        var stack = [root], n = 0
        while (stack.length > 0 && n < 4000) {
            var it = stack.pop()
            n++
            if (!it || it.visible === false || it.opacity === 0) continue
            if (isText(it)) {
                // (a Text's children — a TextFx and the copy it draws — are not walked)
                var fx = fxOf(it)
                if (fx) fx.start()
                else if (it.text !== "") fxC.createObject(it)
                continue
            }
            var c = it.children
            for (var i = c.length - 1; i >= 0; i--) stack.push(c[i])
        }
    }
}
