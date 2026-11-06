import QtQuick
import Quickshell
import "../core"
import "bar/appicon.js" as AppIcons

// A hover preview in the Stage's peek (I284, I285; docs/ux/hover-previews.md). `window:<id>`: the window as last seen, its title,
// its app, how long ago when that is more than a minute. `workspace:<id>`: its windows side by side in niri's column order, or
// the whole workspace as last seen when some of them have no picture of their own. A pure view of `svc.previews`; nothing
// here runs while no peek is up, and no clock ticks on it: the age is read when the peek opens.
Column {
    id: pv
    property string source: ""
    property int maxWidth: 400
    property color fg: Theme.fg
    property color dim: Theme.dim
    spacing: Theme.xs

    readonly property string kind: source.split(":")[0]
    readonly property int itemId: Number(source.split(":")[1] || -1)
    readonly property var doc: Store.docs["svc.previews"] || ({})
    readonly property var ws: Store.docs["svc.workspaces"] || ({})
    readonly property var windows: Array.isArray(ws.windows) ? ws.windows : []

    function winOf(id) {
        for (var i = 0; i < windows.length; i++) if (windows[i].id === id) return windows[i]
        return null
    }
    function nameOf(w) {
        var appId = String(w && w.app_id || "")
        var e = AppIcons.entryFor(DesktopEntries, appId)
        return e && e.name ? String(e.name) : (appId !== "" ? appId : I18n.tr("tasks.peek.untitled"))
    }
    function picOf(id) { var p = (doc.windows || ({}))[id]; return p && p.path ? p : null }
    // How long ago, when it is long enough to matter (Shōjiki: this is not the window now).
    function ago(at) {
        if (!at) return ""
        var min = Math.floor((Date.now() - at) / 60000)
        if (min < 1) return ""
        return min < 60 ? I18n.tr("tasks.preview.ago_min").replace("{n}", min)
                        : I18n.tr("tasks.preview.ago_hour").replace("{n}", Math.floor(min / 60))
    }

    // ---- a window ----
    property string title: ""
    function fetchTitle() {
        if (kind !== "window" || itemId < 0) return
        var want = source
        Store.act("window.title", { id: itemId }, function (m) {
            if (want === pv.source) pv.title = m && m.data && m.data.title ? String(m.data.title) : ""
        })
    }
    onSourceChanged: { title = ""; fetchTitle() }
    readonly property var win: kind === "window" ? winOf(itemId) : null
    readonly property var winPic: kind === "window" ? picOf(itemId) : null

    Image {
        visible: pv.winPic !== null
        readonly property real k: pv.winPic ? Math.min(1, pv.maxWidth / pv.winPic.w) : 1
        width: pv.winPic ? Math.round(pv.winPic.w * k) : 0
        height: pv.winPic ? Math.round(pv.winPic.h * k) : 0
        source: pv.winPic ? "file://" + pv.winPic.path : ""
        cache: false
        smooth: true
        Accessible.ignored: true
    }
    PeekLines {
        visible: pv.kind === "window"
        maxWidth: pv.maxWidth
        fg: pv.fg
        dim: pv.dim
        lines: {
            if (pv.kind !== "window") return []
            var out = [pv.title !== "" ? pv.title : I18n.tr("tasks.peek.untitled"), pv.nameOf(pv.win)]
            var when = pv.winPic ? pv.ago(pv.winPic.at) : ""
            if (!pv.winPic) out.push(I18n.tr("tasks.preview.never"))
            else if (when !== "") out.push(when)
            return out
        }
    }

    // ---- a workspace ----
    readonly property var space: kind === "workspace" ? ((doc.workspaces || ({}))[itemId] || ({})) : ({})
    readonly property var order: Array.isArray(space.windows) ? space.windows.filter(function (id) { return pv.winOf(id) !== null }) : []
    readonly property var still: space.still && space.still.path ? space.still : null
    readonly property bool allSeen: {
        if (order.length === 0) return false
        for (var i = 0; i < order.length; i++) if (!picOf(order[i])) return false
        return true
    }
    readonly property var pill: {
        var o = ws.outputs || {}
        for (var k in o) {
            if (k === "*") continue
            for (var i = 0; i < o[k].length; i++) if (o[k][i].id === itemId) return o[k][i]
        }
        return null
    }
    // The tiles' height: 120, less when they would not fit side by side.
    readonly property real tileH: {
        if (!allSeen) return 0
        var w = 0
        for (var i = 0; i < order.length; i++) { var p = picOf(order[i]); w += p.w / p.h }
        var gaps = Theme.xs * Math.max(0, order.length - 1)
        return Math.max(40, Math.min(120, (maxWidth - gaps) / w))
    }

    Text {
        visible: pv.kind === "workspace"
        width: Math.min(pv.maxWidth, implicitWidth)
        elide: Text.ElideRight
        color: pv.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: pv.pill ? (pv.pill.name ? String(pv.pill.name) : I18n.tr("tasks.preview.workspace").replace("{n}", pv.pill.idx)) : ""
    }
    Row {
        visible: pv.allSeen
        spacing: Theme.xs
        Repeater {
            model: pv.allSeen ? pv.order : []
            Column {
                required property var modelData
                readonly property var pic: pv.picOf(modelData)
                spacing: 2
                Image {
                    id: tile
                    height: pv.tileH
                    width: parent.pic ? Math.round(parent.pic.w / parent.pic.h * height) : 0
                    source: parent.pic ? "file://" + parent.pic.path : ""
                    cache: false
                    smooth: true
                }
                Text {
                    width: tile.width
                    elide: Text.ElideRight
                    color: pv.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: pv.nameOf(pv.winOf(parent.modelData))
                }
            }
        }
    }
    Image {
        visible: !pv.allSeen && pv.still !== null
        readonly property real k: pv.still ? Math.min(1, pv.maxWidth / pv.still.w) : 1
        width: pv.still ? Math.round(pv.still.w * k) : 0
        height: pv.still ? Math.round(pv.still.h * k) : 0
        source: !pv.allSeen && pv.still ? "file://" + pv.still.path : ""
        cache: false
        smooth: true
    }
    PeekLines {
        visible: pv.kind === "workspace"
        maxWidth: pv.maxWidth
        fg: pv.dim
        dim: pv.dim
        lines: {
            if (pv.kind !== "workspace") return []
            var out = []
            if (pv.order.length === 0) out.push(I18n.tr("tasks.preview.empty"))
            else if (!pv.allSeen) {
                // Names, for a workspace whose windows have no picture of their own.
                var names = pv.order.slice(0, 5).map(function (id) { return pv.nameOf(pv.winOf(id)) })
                out.push(names.join(" · ") + (pv.order.length > 5 ? " +" + (pv.order.length - 5) : ""))
                if (!pv.still) out.push(I18n.tr("tasks.preview.never"))
            }
            var when = pv.still ? pv.ago(pv.still.at) : ""
            if (when !== "" && pv.order.length > 0) out.push(when)
            return out
        }
    }
}
