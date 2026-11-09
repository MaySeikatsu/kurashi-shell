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
    // I284: last-seen stills while this module is out and its previews are on; the pointer's arrival keeps what is on screen.
    readonly property bool previews: cfg.valueOf("modules.windows.previews", true) === true
    Watch { doc: "svc.previews"; active: m.live && m.previews }
    HoverHandler { onHoveredChanged: if (hovered && m.previews) Store.act("preview.refresh", { output: m.output }) }
    // B48: elastic — the room the bar's fit gives it along its edge (px, ModuleBase `room`); the list fits as many buttons
    // as it holds, the rest under "+N". Full: every window (or `max`); least: the "+N" button alone.
    readonly property int wanted: m.most > 0 ? Math.min(tasks.length, m.most) : tasks.length
    elastic: !vertical && tasks.length > 1
    // (the list's grid spaces its Repeater as one more item: n buttons draw n × (button + gap), measured 144 px for six)
    fullW: vertical ? width : wanted * (list.btn + list.spacing)
    minW: vertical ? width : list.btn + list.spacing
    // It draws whole buttons: the width a room holds (barfit `snap`).
    function snapW(px) {
        var pitch = list.btn + list.spacing
        return Math.min(m.wanted, Math.max(1, Math.floor(px / pitch))) * pitch
    }
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
            var fits = Math.max(1, Math.floor(m.room / (btn + spacing)))
            return m.most > 0 ? Math.min(fits, m.most) : fits
        }
        middleCloses: cfg.valueOf("modules.windows.middle_close", true) === true
        previews: m.previews
        pillAt: function (sx, sy) { return m.link ? m.link.pillAt(sx, sy, Theme.gap / 2 + 1) : null }
        pillBoxes: function () { return m.link ? m.link.boxes() : [] }
        onDragWsChanged: if (m.link) m.link.dragWs = dragWs
        onModuleMenu: Store.act("tray.menu.open", { id: "module:windows" })
    }
}
