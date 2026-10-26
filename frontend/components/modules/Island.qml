import QtQuick
import Quickshell
import "../../core"
import "../island"
import ".." as C

// Module `island`: the island (runtime.island.main) — its face, the secondary glyph and "+N", the peek and the slots the
// user bound (bindings `island.main`, dispatched by the daemon). In a column it is a column (I85). Where it stands is told
// to IslandGeom (`place`: read when a surface asks, nothing per frame), so the Stage grows its card out of the pill wherever
// the zone puts it; and to Peeks (the edge and the window's place), so its peek hangs beside it.
ModuleBase {
    id: m
    Watch { doc: "runtime.island.main"; active: m.live }
    Watch { doc: "bindings"; active: m.live }
    readonly property var island: Store.docs["runtime.island.main"] || ({})
    readonly property var bindings: Store.docs["bindings"] || ({})
    width: isl.width
    height: isl.height
    function geo() { return [["island", isl]] }

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
    readonly property string peekKey: qsw ? [m.output, m.edge, Math.round(origin.x), Math.round(origin.y)].join("|") : ""
    onPeekKeyChanged: if (peekKey !== "") Peeks.place("island:main", m.output, m.edge, origin.x, origin.y)
    Component.onCompleted: if (placing) IslandGeom.place(m.output, m.edge, m.where, m)
    Component.onDestruction: {
        Peeks.unplace("island:main", m.output)
        IslandGeom.unplace(m.output, m)
    }
}
