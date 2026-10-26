import QtQuick

// Where a mod panel is at rest in a sidebar's window (W30; the optional panel property `placement`, next to
// `fillHeight`): `{output, side, inset, top, width, height}` — the panel's rect measured from the window's anchored side
// edge and from its top (the usable area's top: the sidebar window is anchored top + bottom + side, exclusive zone 0) —
// or null while the panel moves (the sidebar's slide, a page sliding over the sections, a scroll), is clipped by a scroll
// view or the window, or has no window. A panel that shows content of another process (the web dock's pages) maps it
// there. Generic: no mod is named here. Ma: it works only on the window's swapped frames (none while the sidebar is idle)
// and on the target's own size changes; the settle timer runs only after a move.
QtObject {
    id: pl
    property Item target: null
    property var win: null                  // the sidebar's window (the caller's `Window.window`)
    property string output: ""              // the output it is on (the caller's `Screen.name`)
    property string side: "left"            // the sidebar's side: the edge its window is anchored to
    // Where the usable area starts in the window (W44: the sidebar's window stands from the screen's edges, ignoring
    // zones; the host maps the page in the usable area, so the rect is reported from there): x from the anchored side.
    property point origin: Qt.point(0, 0)
    readonly property var value: _value
    property var _value: null
    property string _last: ""
    // The rect must keep still this long before it counts as at rest (a spring's tail moves less than a pixel a frame).
    property int settleMs: 160

    function sceneRect() {
        if (!target || !target.visible || !win) return null
        var w = win
        var p = target.mapToItem(null, 0, 0)
        var r = { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(target.width), h: Math.round(target.height),
                  ww: Math.round(w.width), wh: Math.round(w.height) }
        if (r.w < 1 || r.h < 1) return null
        if (r.x < 0 || r.y < 0 || r.x + r.w > r.ww || r.y + r.h > r.wh) return null
        // Every clipping ancestor (a scroll view) must show the whole rect.
        for (var a = target.parent; a; a = a.parent) {
            if (!a.clip) continue
            var q = a.mapToItem(null, 0, 0)
            if (r.x < Math.round(q.x) - 1 || r.y < Math.round(q.y) - 1
                || r.x + r.w > Math.round(q.x + a.width) + 1 || r.y + r.h > Math.round(q.y + a.height) + 1) return null
        }
        return r
    }
    // A change of the rect: the placement is withdrawn at once and offered again once the rect has kept still.
    function check() {
        var r = sceneRect()
        var key = r ? [r.x, r.y, r.w, r.h, r.ww, r.wh].join(",") : ""
        if (key === _last) return
        _last = key
        _value = null
        if (r) settle.restart()
        else settle.stop()
    }
    function commit() {
        var r = sceneRect()
        if (!r) { _value = null; return }
        var w = win
        var out = output !== "" ? output : (w && w.screen ? String(w.screen.name) : "")
        _value = { output: out, side: side, inset: (side === "right" ? r.ww - r.x - r.w : r.x) - Math.round(origin.x),
                   top: r.y - Math.round(origin.y), width: r.w, height: r.h }
    }
    property Timer settle: Timer {
        interval: pl.settleMs
        onTriggered: pl.commit()
    }
    property Connections frames: Connections {
        target: pl.target ? pl.win : null
        function onFrameSwapped() { pl.check() }
        function onWidthChanged() { pl.check() }
        function onHeightChanged() { pl.check() }
    }
    property Connections size: Connections {
        target: pl.target
        function onWidthChanged() { pl.check() }
        function onHeightChanged() { pl.check() }
        function onVisibleChanged() { pl.check() }
    }
    onTargetChanged: check()
    onWinChanged: check()
    onOutputChanged: { _last = ""; check() }
    onOriginChanged: { _last = ""; check() }
    Component.onCompleted: check()
}
