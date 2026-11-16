import QtQuick
import "../core"

// Where a sheet stands on an output (K165; the terminal's drop-down and the top and bottom sidebars share it): joined to
// the main bar's centre (`place = bar`: `widthPct` of the screen wide), along an edge (`edge`: `lengthPct` of it, the
// whole edge less what the other edges' bars and bands take), centred (`center`) or at a corner with offsets
// (`position`). `heightFrac` is how far it reaches out of its edge, as a share of the screen. Numbers only: the window
// and the drawing are the surface's (SheetFrame). Needs `runtime.layout` watched by its owner while it is used.
QtObject {
    id: g
    property string outName: ""
    property real scrW: 1920
    property real scrH: 1080
    property string place: "bar"
    property string edgeSet: "top"
    property real widthPct: 60
    property real lengthPct: 100
    property real heightFrac: 0.45
    property string anchor: "top-left"
    property real offsetX: 0
    property real offsetY: 0

    readonly property var lay: ShellLayout.of(outName)
    function edgeLay(e) { return (lay && lay.edges && lay.edges[e]) || {} }
    function band(e) { var f = lay ? lay.frame : null; return f && f.on && f.band ? (f.band[e] || 0) : 0 }
    function barOn(e) { var ed = edgeLay(e); return ed.bar === true && ed.visibility !== "hidden" }
    // How far the free area stands off edge `e`: the frame's band and a bar shown there (framegeom.js holeSide).
    function hole(e) { return band(e) + (barOn(e) ? Math.max(0, edgeLay(e).inset || 0) + Theme.barH : 0) }
    // The main bar: the top bar on this output, else the bottom one; a side bar is not one (docs/ux/terminal.md).
    readonly property string mainBar: barOn("top") ? "top" : (barOn("bottom") ? "bottom" : "")
    // `bar` without a horizontal bar here stands at the top edge (the owner's Settings say why: `noBar`).
    readonly property bool noBar: place === "bar" && mainBar === ""
    readonly property string mode: noBar ? "edge" : place
    readonly property string edge: mode === "bar" ? mainBar : (noBar ? "top" : edgeSet)
    readonly property bool attached: mode === "bar" || mode === "edge"
    readonly property bool sideways: attached && (edge === "left" || edge === "right")
    // A sheet hangs from what stands on its edge: a bar or the frame's band draws the join; a bare screen edge does not.
    readonly property bool joins: attached && Theme.surfaceJoin && hole(edge) > 0
    // The sheet's box (logical px): across its edge × out of it.
    readonly property real sheetW: Math.round(sideways ? scrW * heightFrac
        : scrW * (mode === "edge" ? lengthPct : widthPct) / 100 - (mode === "edge" && lengthPct >= 100 ? hole("left") + hole("right") : 0))
    readonly property real sheetH: Math.round(sideways ? scrH * lengthPct / 100 - (lengthPct >= 100 ? hole("top") + hole("bottom") : 0)
        : scrH * heightFrac)
    // The fillets' room round a joined sheet.
    readonly property real pad: joins ? Theme.rJoin : 0
    // The window: the sheet plus its fillets, placed against its edge or floating.
    readonly property real winW: sheetW + (joins && !sideways ? 2 * pad : 0)
    readonly property real winH: sheetH + (joins && sideways ? 2 * pad : 0)
    readonly property var anchorXY: {
        var x = 0, y = 0
        var left = hole("left"), right = hole("right"), top = hole("top"), bottom = hole("bottom")
        if (anchor.indexOf("left") >= 0) x = left + Theme.gap
        else if (anchor.indexOf("right") >= 0) x = scrW - right - Theme.gap - winW
        else x = (scrW - winW) / 2
        if (anchor.indexOf("top") >= 0) y = top + Theme.gap
        else if (anchor.indexOf("bottom") >= 0) y = scrH - bottom - Theme.gap - winH
        else y = (scrH - winH) / 2
        return { x: x + offsetX, y: y + offsetY }
    }
    readonly property real winX: Math.round(mode === "position" ? anchorXY.x
        : mode === "center" ? (scrW - winW) / 2
        : edge === "left" ? hole("left") : edge === "right" ? scrW - hole("right") - winW
        : (scrW - winW) / 2)
    readonly property real winY: Math.round(mode === "position" ? anchorXY.y
        : mode === "center" ? (scrH - winH) / 2
        : edge === "top" ? hole("top") : edge === "bottom" ? scrH - hole("bottom") - winH
        : (scrH - winH) / 2)
}
