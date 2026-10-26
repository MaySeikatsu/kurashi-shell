pragma Singleton
import QtQuick

// The shared hover strips at the screen edges (K71, docs/ux/layout.md "Visibility"): one thin input-only window per output
// and edge, made only while something on that edge reveals on hover (`claim`), shared by every such consumer — the bar,
// the dock, a sidebar, an edge module group — instead of one edge window each (a layer window costs ~3.5 MiB, I11).
// The strip reports where the pointer is along its edge; each consumer's EdgeReveal decides from its own span. Plain
// state, no timers here (Ma).
QtObject {
    // { "<output>/<edge>": { "<consumer key>": true } } — who wants the strip.
    property var claims: ({})
    // { "<output>/<edge>": px along the edge (from its left or top end), or absent while the pointer is not on the strip }.
    property var pos: ({})

    function stripKey(output, edge) { return output + "/" + edge }
    function claim(output, edge, key) {
        if (!output || !edge || !key) return
        var k = stripKey(output, edge), c = claims[k]
        if (c && c[key]) return
        var n = Object.assign({}, claims)
        n[k] = Object.assign({}, c || {})
        n[k][key] = true
        claims = n
    }
    function release(output, edge, key) {
        var k = stripKey(output, edge), c = claims[k]
        if (!c || !c[key]) return
        var n = Object.assign({}, claims), m = Object.assign({}, c)
        delete m[key]
        if (Object.keys(m).length === 0) delete n[k]
        else n[k] = m
        claims = n
    }
    function wanted(output, edge) { var c = claims[stripKey(output, edge)]; return !!c && Object.keys(c).length > 0 }

    function setPos(output, edge, p) {
        var k = stripKey(output, edge)
        if (p < 0) {
            if (pos[k] === undefined) return
            var n = Object.assign({}, pos); delete n[k]; pos = n
        } else if (pos[k] !== p) {
            var m = Object.assign({}, pos); m[k] = p; pos = m
        }
    }
    // The pointer's place along the edge, or -1 while it is not on the strip.
    function posOf(output, edge) { var p = pos[stripKey(output, edge)]; return p === undefined ? -1 : p }
}
