import QtQuick
import Quickshell
import "../../core"
import "../island"
import ".." as C

// Module `island`: the island (runtime.island.main) — its face, the secondary glyph and "+N", the peek and the slots the
// user bound (bindings `island.main`, dispatched by the daemon). In a column it is a column (I85). Where it stands is told
// to IslandGeom (`place`: read when a surface asks, nothing per frame), so the Stage grows its card out of the pill wherever
// the zone puts it — a bar's zone or, standalone (W45, user point 11), an edge module group; its peek hangs from this host's
// edge and window (PeekSource asks peekPlace(), row 514). Enter on the host's tab stop does what the left click does.
ModuleBase {
    id: m
    Watch { doc: "runtime.island.main"; active: m.live }
    Watch { doc: "bindings"; active: m.live }
    readonly property var island: Store.docs["runtime.island.main"] || ({})
    readonly property var bindings: Store.docs["bindings"] || ({})
    width: isl.width
    height: isl.height
    function geo() { return [["island", isl]] }
    // The face it shows, and that face's line when the daemon gives one (its peek's text).
    readonly property string faceName: I18n.tr("island.face." + (m.island.face || "clock"))
    readonly property string faceLine: {
        var t = (m.island.detail || ({}))[m.island.face || "clock"]
        return t === undefined || t === null ? "" : String(t)
    }
    a11yName: I18n.tr("layout.module.island") + ": " + faceName + (faceLine !== "" ? " · " + faceLine : "")
    function activate() {
        if ((m.bindings["island.main"] || ({}))["left"] !== undefined)
            Store.act("input.dispatch", {component: "island.main", slot: "left"})
        else Store.act("island.expand", {})
    }

    C.Island {
        id: isl
        vertical: m.vertical
        face: m.island.face || "clock"
        reason: m.island.reason || "default"
        slots: m.bindings["island.main"] || ({})
        peekOutput: m.output
        // The user's binding decides what a slot does; an absent slot never reaches here.
        onActivated: slot => Store.act("input.dispatch", {component: "island.main", slot: slot})
    }

    readonly property var qsw: Window.window ? QsWindow.window : null
    readonly property point origin: qsw ? Light.originOf(qsw) : Qt.point(0, 0)
    // The island's centre from the output's centre (px), read when the Stage asks (IslandGeom.pillOf).
    function where() {
        if (!m.qsw || !m.screen) return 0
        var p = m.mapToItem(null, m.width / 2, 0)
        return Math.round(m.origin.x + p.x - m.screen.width / 2)
    }
    readonly property bool placing: m.anchored && !m.vertical && m.output !== ""
    onPlacingChanged: placing ? IslandGeom.place(m.output, m.edge, m.where, m) : IslandGeom.unplace(m.output, m)
    Component.onCompleted: if (placing) IslandGeom.place(m.output, m.edge, m.where, m)
    Component.onDestruction: IslandGeom.unplace(m.output, m)
}
