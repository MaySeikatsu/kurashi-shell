import QtQuick
import Quickshell
import "../../core"
import "../island"
import ".."

// Module `tray` (K23): the StatusNotifierItems (svc.tray), one icon each, as thick as the host; none while the tray service
// is unavailable, and Passive items stay hidden (nothing to show). In a column each icon is a slot of the host's fit: the
// column's end hides first. A menu request goes to the host (`menuRequested`: the shell opens it on this output's Stage);
// activate and secondary are sent here with the click's screen point. Each icon's peek names its title and tooltip (K35).
ModuleBase {
    id: m
    Watch { doc: "svc.tray"; active: m.live }
    readonly property var doc: Store.docs["svc.tray"] || ({})
    readonly property var items: doc.available === true
        ? (doc.items || []).filter(function (it) { return it.status !== "Passive" }) : []
    signal menuRequested(string id)
    present: items.length > 0
    // The icons the host's fit gives it (all of them in a row).
    readonly property int shownN: Math.max(0, Math.min(items.length, fitSlots))
    slotHeights: items.map(function () { return m.thickness })
    width: vertical ? col.implicitWidth : row.implicitWidth
    height: vertical ? col.implicitHeight : row.implicitHeight
    function geo() {
        var r = vertical ? repV : repH, out = []
        for (var j = 0; j < r.count; j++) out.push(["tray" + j, r.itemAt(j)])
        return out
    }

    readonly property var qsw: Window.window ? QsWindow.window : null
    // Screen coordinates of a point in `item` (the SNI calls take them): the window's place on its output, from Light.
    function screenPoint(item, x, y) {
        var p = item.mapToItem(null, x, y)
        var o = qsw ? Light.originOf(qsw) : Qt.point(0, 0)
        var s = m.screen
        return { x: Math.round((s ? s.x : 0) + o.x + p.x), y: Math.round((s ? s.y : 0) + o.y + p.y) }
    }
    function request(action, id, item, x, y) {
        if (action === "menu") { m.menuRequested(id); return }
        var p = screenPoint(item, x, y)
        Store.act(action === "secondary" ? "tray.secondary" : "tray.activate", {id: id, x: p.x, y: p.y})
    }

    Component {
        id: icon
        TrayIcon {
            id: ticon
            required property var modelData
            required property int index
            visible: index < m.shownN
            title: modelData.title ?? ""
            iconName: modelData.icon_name ?? ""
            iconTheme: modelData.icon_theme_path ?? ""
            pixmap: (modelData.icon_pixmap && modelData.icon_pixmap.png_base64)
                ? "data:image/png;base64," + modelData.icon_pixmap.png_base64 : ""
            attention: modelData.status === "NeedsAttention"
            hasMenu: modelData.has_menu === true
            menuOnly: modelData.item_is_menu === true
            tip: modelData.tooltip ?? ""
            // The hover peek names the item's title and tooltip (K35, B9); an item with neither has nothing to show.
            peekSource: (modelData.title || modelData.tooltip) ? "tray:" + modelData.id : ""
            peekOutput: m.output
            onRequested: (action, x, y) => m.request(action, modelData.id, ticon, x, y)
            onScrolled: (delta, orientation) =>
                Store.act("tray.scroll", {id: modelData.id, delta: delta, orientation: orientation})
            // W34: the item's menu grows out of it (IslandGeom's origins; top and bottom hosts).
            AnchorReport { target: ticon; key: "tray:" + ticon.modelData.id; output: m.output; enabled: m.anchored && !m.vertical }
            // Its peek hangs off this host's edge (Peeks: one output may have several bars).
            readonly property string placeKey: peekSource !== "" && m.qsw ? [m.output, m.edge, Light.originOf(m.qsw).x, Light.originOf(m.qsw).y].join("|") : ""
            onPlaceKeyChanged: if (placeKey !== "") { var o = Light.originOf(m.qsw); Peeks.place(peekSource, m.output, m.edge, o.x, o.y) }
            Component.onDestruction: if (peekSource !== "") Peeks.unplace(peekSource, m.output)
        }
    }
    Row {
        id: row
        visible: !m.vertical
        spacing: Theme.pad
        Repeater { id: repH; model: m.vertical ? [] : m.items; delegate: icon }
    }
    Column {
        id: col
        visible: m.vertical
        spacing: Theme.pad
        Repeater { id: repV; model: m.vertical ? m.items : []; delegate: icon }
    }
}
