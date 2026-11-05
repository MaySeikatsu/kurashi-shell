import QtQuick
import "../../core"
import "../bar"
import "../../surfaces" as S

// Module `windows`: the windows of this output's active workspace (svc.workspaces `tasks`; W36, docs/ux/window-list.md),
// one icon each, click focuses; as many as `room` (px along the host) holds, the rest as "+N". A window dragged onto a
// workspace chip of the same host moves there (the link's chips).
ModuleBase {
    id: m
    Watch { doc: "svc.workspaces"; active: m.live }
    readonly property var doc: Store.docs["svc.workspaces"] || ({})
    readonly property var tasks: {
        var t = doc.tasks || {}
        return t[m.output] || t["*"] || []
    }
    readonly property var pills: {
        var o = doc.outputs || {}
        return o[m.output] || o["*"] || []
    }
    // I408: its own options (`modules.windows.*`, its right-click menu).
    S.BarConfig { id: cfg; screen: null }
    readonly property int most: Number(cfg.valueOf("modules.windows.max", 0))
    // The room the host leaves it, along its edge (px); the list fits as many buttons as it holds.
    property real room: 1e6
    present: tasks.length > 0
    busy: list.menuOpen
    width: list.width
    height: list.height
    function geo() { return [["tasks", m]] }

    TaskList {
        id: list
        tasks: m.tasks
        vertical: m.vertical
        edge: m.edge
        screen: m.screen
        pills: m.pills
        live: m.live
        maxCount: {
            var fits = Math.max(1, Math.floor((m.room + spacing) / (btn + spacing)))
            return m.most > 0 ? Math.min(fits, m.most) : fits
        }
        middleCloses: cfg.valueOf("modules.windows.middle_close", true) === true
        pillAt: function (sx, sy) { return m.link ? m.link.pillAt(sx, sy, Theme.gap / 2 + 1) : null }
        pillBoxes: function () { return m.link ? m.link.boxes() : [] }
        onDragWsChanged: if (m.link) m.link.dragWs = dragWs
        onModuleMenu: Store.act("tray.menu.open", { id: "module:windows" })
    }
}
