pragma Singleton
import QtQuick

// ShellLayout (not `Layout`: QtQuick.Layouts owns that attached name). Where the edge surfaces stand (K71, PROTOCOL §3.1): the daemon's `runtime.layout`, read per output. Renderers draw what
// it says and never re-derive an inset, a join or who holds an edge's exclusive zone. Each surface that reads it holds its
// own `Watch { doc: "runtime.layout"; active: <shown> }` (Ma: nothing is subscribed for a surface nobody sees); this only
// looks the output up. Until the document arrives (or for an output it does not name yet) the `"*"` entry, and before any
// document the schema defaults: one dynamic top bar, no frame.
QtObject {
    readonly property var doc: Store.docs["runtime.layout"] || ({})
    readonly property int gap: doc.gap !== undefined ? doc.gap : 8
    readonly property int joinRadius: doc.join_radius !== undefined ? doc.join_radius : 16
    readonly property int revealDelay: doc.reveal_delay_ms !== undefined ? doc.reveal_delay_ms : 250

    readonly property var fallback: ({
        frame: { on: false, thickness: 8, radius: 16, reserve: true, band: { top: 0, bottom: 0, left: 0, right: 0 } },
        edges: {
            top: { bar: true, size: 32, draw: "dynamic", draw_source: "auto", visibility: "always", inset: 0, reserve: 32,
                   reserve_source: "auto", holder: "bar", zones: { start: [], center: [], end: [] } },
            bottom: { bar: false, draw: "dynamic", draw_source: "auto", visibility: "always", inset: 0, reserve: 0,
                      reserve_source: "auto", holder: "none", zones: { start: [], center: [], end: [] } },
            left: { bar: false, draw: "dynamic", draw_source: "auto", visibility: "always", inset: 0, reserve: 0,
                    reserve_source: "auto", holder: "none", zones: { start: [], center: [], end: [] } },
            right: { bar: false, draw: "dynamic", draw_source: "auto", visibility: "always", inset: 0, reserve: 0,
                     reserve_source: "auto", holder: "none", zones: { start: [], center: [], end: [] } }
        },
        sidebars: {}, unplaced: [], problems: []
    })

    // The layout of the output named `name` ("" or unknown: the "*" entry, else the fallback).
    function of(name) {
        var o = doc.outputs || {}
        return (name && o[name]) || o["*"] || fallback
    }
    function edgeOf(name, edge) { var l = of(name); return (l.edges && l.edges[edge]) || fallback.edges[edge] }
    function bandOf(name, edge) { var f = of(name).frame; return f && f.on && f.band ? (f.band[edge] || 0) : 0 }
}
