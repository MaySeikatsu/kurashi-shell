import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../core"
import ".."
import "appicon.js" as AppIcons

// The bar's window list (session 9 K44; W36: I102, I137; docs/ux/window-list.md): one button per window of the output's
// active workspace (`svc.workspaces.tasks`), in a row (top and bottom bars) or a column (side bars). Click focuses,
// middle-click closes, a drag onto a workspace chip moves the window there, right-click opens a menu (the keyboard path
// to close and move); a rest shows the window's title, fetched then (`window.title`: titles stay out of the document).
// An urgent window hops once (with the theme's spring), then keeps a steady mark. A pure view: every press is an action.
// Ma: no timer runs while nothing is hovered; the peek and the menu exist only while shown.
Item {
    id: tl
    property var tasks: []
    property bool vertical: false
    property string edge: "top"
    property var screen: null
    // This output's workspaces (the menu's "Move to workspace N").
    property var pills: []
    // How many buttons fit; past that the last slot is "+N".
    property int maxCount: 12
    // The bar is shown: the hop runs only then.
    property bool live: true
    // The bar's hit test for a drag: a scene point → the workspace under it ({id, idx, …}) or null.
    property var pillAt: function (x, y) { return null }
    // The workspace chip a drag is over (the bar rings it), else -1.
    property int dragWs: -1
    // Test only (the log below): the chips' boxes in the bar's window, `[{id, x, y, w, h}]`.
    property var pillBoxes: function () { return [] }

    readonly property int btn: Theme.barH - 12
    readonly property int spacing: Theme.xs
    readonly property string outName: screen ? screen.name : ""
    readonly property bool logOn: Quickshell.env("KURASHI_TASKS_LOG") === "1"

    // The model is the ids, remade only when the order changes: a focus or urgency change must not remake the buttons
    // (the hop starts on a change of `urgent` inside a button).
    readonly property var byId: {
        var m = {}
        for (var i = 0; i < tasks.length; i++) m[tasks[i].id] = tasks[i]
        return m
    }
    readonly property bool overflow: tasks.length > Math.max(1, maxCount)
    readonly property int shownN: overflow ? Math.max(0, maxCount - 1) : tasks.length
    readonly property int moreN: tasks.length - shownN
    readonly property string idsJson: JSON.stringify(tasks.slice(0, shownN).map(function (t) { return t.id }))
    property var ids: []
    onIdsJsonChanged: { ids = JSON.parse(idsJson); requestLog() }
    onTasksChanged: requestLog()
    Component.onCompleted: { ids = JSON.parse(idsJson); requestLog() }

    implicitWidth: grid.implicitWidth
    implicitHeight: grid.implicitHeight
    width: implicitWidth
    height: implicitHeight

    // DesktopEntries fills in asynchronously; its change re-runs every lookup.
    property int entriesRev: 0
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() { tl.entriesRev++; tl.requestLog() }
    }
    readonly property var allWindows: {
        var w = (Store.docs["svc.workspaces"] || ({})).windows
        return Array.isArray(w) ? w : []
    }
    function workspaceOf(id) {
        for (var i = 0; i < allWindows.length; i++) if (allWindows[i].id === id) return allWindows[i].workspace
        return null
    }
    function entryOf(appId) { var rev = entriesRev; return AppIcons.entryFor(DesktopEntries, appId) }
    function nameOf(w) {
        var appId = String(w && w.app_id || "")
        var e = entryOf(appId)
        return e && e.name ? String(e.name) : (appId !== "" ? appId : I18n.tr("tasks.peek.untitled"))
    }
    // A hop away from the screen edge, along the bar's thickness.
    readonly property int hopDir: edge === "bottom" || edge === "right" ? -1 : 1

    // ---- actions ----
    function focusWin(id) { closeMenu(); Store.act("window.focus", { id: id }) }
    function closeWin(id) { closeMenu(); Store.act("window.close", { id: id }) }
    function run(action, args) {
        menuError = ""
        Store.act(action, args, function (m, err) {
            if (err) tl.menuError = I18n.tr("tasks.error.action")
            else tl.closeMenu()
        })
    }

    // ---- drag to a workspace ----
    property int dragId: -1
    property var dragTile: null
    property point ghostAt: Qt.point(0, 0)
    function dragStart(t) {
        peekTimer.stop(); peekId = -1; closeMenu()
        dragTile = t
        dragId = t.modelData
    }
    function dragMove(p) {
        if (dragId < 0) return
        var ws = pillAt(p.x, p.y)
        dragWs = ws && ws.id !== undefined ? ws.id : -1
        dragIdx = ws && ws.idx !== undefined ? ws.idx : 0
        ghostAt = tl.mapFromItem(null, p.x, p.y)
    }
    property int dragIdx: 0
    function dragEnd() {
        var id = dragId, ws = dragWs
        dragId = -1; dragWs = -1; dragTile = null
        if (id >= 0 && ws >= 0 && ws !== workspaceOf(id)) {
            Store.act("window.move", { id: id, workspace: ws })
            if (logOn) console.log("tasks-move " + id + " " + ws)
        }
    }

    // ---- peek: the title, fetched after a rest ----
    property int peekCandidate: -1
    property var peekTile: null
    property int peekId: -1
    property string peekTitle: ""
    // "loading", "ok", "none" (no title), "gone" (the request failed)
    property string peekState: ""
    property int peekSeq: 0
    Timer { id: peekTimer; interval: 400; onTriggered: tl.askTitle() }
    function hoverOn(t) {
        peekCandidate = t.modelData
        peekTile = t
        if (dragId < 0 && menuId === -1) peekTimer.restart()
    }
    function hoverOff(t) {
        if (peekCandidate !== t.modelData) return
        peekTimer.stop()
        peekCandidate = -1
        peekId = -1
    }
    function fetchTitle(id, done) {
        var seq = ++peekSeq
        Store.act("window.title", { id: id }, function (m, err) {
            if (seq !== tl.peekSeq) return
            if (err) { done("gone", ""); return }
            var t = m && m.data ? m.data.title : null
            done(t ? "ok" : "none", t ? String(t) : "")
        })
    }
    function askTitle() {
        var id = peekCandidate
        if (id < 0) return
        peekId = id
        peekState = "loading"
        peekTitle = ""
        fetchTitle(id, function (state, title) {
            tl.peekState = state
            tl.peekTitle = title
            if (tl.logOn) console.log("tasks-peek " + id + " " + state + " " + title)
        })
    }

    // ---- menu: right-click on a button (or a click on "+N") ----
    // menuId: the window's id, -2 for the "+N" list, -1 closed.
    property int menuId: -1
    property rect menuAt: Qt.rect(0, 0, 0, 0)
    property string menuError: ""
    property string menuTitle: ""
    property int menuCurrent: 0
    readonly property bool menuOpen: menuId !== -1
    function closeMenu() { menuId = -1; menuError = "" }
    function openMenu(t, id) {
        peekTimer.stop(); peekId = -1
        menuError = ""; menuCurrent = 0; menuTitle = ""
        var p = t.mapToItem(null, 0, 0)
        var win = t.Window
        var ox = edge === "right" && screen && win ? screen.width - win.width : 0
        var oy = edge === "bottom" && screen && win ? screen.height - win.height : 0
        menuAt = Qt.rect(ox + p.x, oy + p.y, t.width, t.height)
        menuId = id
        if (id >= 0) fetchTitle(id, function (state, title) {
            tl.menuTitle = state === "ok" ? title : (state === "gone" ? I18n.tr("tasks.error.gone") : I18n.tr("tasks.peek.untitled"))
        })
    }
    // The rows: {text, on (enabled), run}.
    readonly property var menuRows: {
        var r = []
        if (menuId === -2) {
            for (var k = shownN; k < tasks.length; k++) {
                var hid = tasks[k]
                r.push({ text: nameOf(hid), on: true, run: (function (id) { return function () { tl.run("window.focus", { id: id }) } })(hid.id) })
            }
            return r
        }
        var w = byId[menuId]
        if (!w) return r
        r.push({ text: I18n.tr("tasks.menu.focus"), on: w.focused !== true, run: function () { tl.run("window.focus", { id: w.id }) } })
        var cur = workspaceOf(w.id)
        for (var i = 0; i < pills.length; i++) {
            var p = pills[i]
            if (p.id === cur) continue
            r.push({ text: I18n.tr("tasks.menu.move").replace("{n}", p.idx), on: true,
                     run: (function (ws) { return function () { tl.run("window.move", { id: w.id, workspace: ws }) } })(p.id) })
        }
        r.push({ text: I18n.tr("tasks.menu.close"), on: true, run: function () { tl.run("window.close", { id: w.id }) } })
        return r
    }
    // A window that went away closes its menu.
    onByIdChanged: if (menuId >= 0 && !byId[menuId]) closeMenu()
    function menuKeyPress(key) {
        if (!menuOpen) return false
        if (key === Qt.Key_Escape) closeMenu()
        else if (key === Qt.Key_Up) menuCurrent = Math.max(0, menuCurrent - 1)
        else if (key === Qt.Key_Down) menuCurrent = Math.min(menuRows.length - 1, menuCurrent + 1)
        else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            var r = menuRows[menuCurrent]
            if (r && r.on) r.run()
        } else return false
        return true
    }

    // ---- the buttons ----
    Grid {
        id: grid
        columns: tl.vertical ? 1 : 1000
        spacing: tl.spacing
        Repeater {
            id: rep
            model: tl.ids
            delegate: Rectangle {
                id: task
                required property var modelData
                required property int index
                readonly property var w: tl.byId[modelData] || ({})
                readonly property string appId: String(w.app_id || "")
                readonly property var entry: tl.entryOf(appId)
                readonly property string name: tl.nameOf(w)
                readonly property bool focusedWin: w.focused === true
                readonly property bool urgent: w.urgent === true
                readonly property string iconKind: icon.kind
                width: tl.btn
                height: tl.btn
                radius: Theme.groups ? Math.min(width / 2, Theme.rFull) : Theme.rSm
                color: focusedWin ? Theme.selected
                    : (hover.hovered || tl.menuId === modelData ? Theme.containerHigh : "transparent")
                border.width: focusedWin ? Theme.outlineW : 0
                border.color: Theme.outlineColor
                opacity: tl.dragId === modelData ? 0.35 : 1
                Accessible.role: Accessible.Button
                Accessible.name: I18n.tr(urgent ? "tasks.a11y.urgent" : (focusedWin ? "tasks.a11y.focused" : "tasks.a11y.window"))
                    .replace("{name}", name)
                Accessible.description: I18n.tr("tasks.a11y.hint")
                onIconKindChanged: tl.requestLog()
                transform: Translate { id: hopT }

                AppIcon {
                    id: icon
                    anchors.centerIn: parent
                    width: parent.width - 4
                    height: width
                    appId: task.appId
                    entry: task.entry
                    color: task.focusedWin ? Theme.fgOnSelected : Theme.fg
                }
                // The focused window's mark (focus is not colour alone): under the button on a top or bottom bar, on its
                // outer side on a side bar.
                Rectangle {
                    visible: task.focusedWin
                    x: tl.vertical ? (tl.edge === "left" ? -4 : parent.width + 1) : (parent.width - width) / 2
                    y: tl.vertical ? (parent.height - height) / 2 : parent.height + 1
                    width: tl.vertical ? 3 : 10
                    height: tl.vertical ? 10 : 3
                    radius: 1.5
                    color: Theme.accent
                }
                // Urgent: a steady dot at the corner (its place, not only its colour, says it), after the hop.
                Rectangle {
                    visible: task.urgent
                    width: 8
                    height: 8
                    radius: 4
                    x: parent.width - width + 2
                    y: -2
                    color: Theme.warning
                    border.width: 1
                    border.color: Theme.surface
                }
                SequentialAnimation {
                    id: hop
                    loops: 3
                    NumberAnimation { target: hopT; property: tl.vertical ? "x" : "y"; to: 4 * tl.hopDir; duration: 110; easing.type: Easing.OutQuad }
                    NumberAnimation { target: hopT; property: tl.vertical ? "x" : "y"; to: 0; duration: 130; easing.type: Easing.InQuad }
                }
                // Only a change to urgent hops (a window that already asked when the bar came up shows the dot alone);
                // reduced motion (`motion.spring.on` false) or a hidden bar: no hop.
                onUrgentChanged: {
                    if (!urgent) { hop.stop(); hopT.x = 0; hopT.y = 0; return }
                    var moves = tl.live && Theme.springOn
                    if (moves) hop.restart()
                    if (tl.logOn) console.log("tasks-urgent " + modelData + " " + (moves ? "hop" : "still"))
                }

                HoverHandler {
                    id: hover
                    onHoveredChanged: hovered ? tl.hoverOn(task) : tl.hoverOff(task)
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: tl.focusWin(task.modelData)
                }
                TapHandler {
                    acceptedButtons: Qt.MiddleButton
                    onTapped: tl.closeWin(task.modelData)
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: tl.openMenu(task, task.modelData)
                }
                DragHandler {
                    id: drag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    onActiveChanged: active ? tl.dragStart(task) : tl.dragEnd()
                    onCentroidChanged: if (active) tl.dragMove(centroid.scenePosition)
                }
            }
        }
        // The windows past the room: "+N"; a click lists them (focus one from there).
        Rectangle {
            id: more
            visible: tl.moreN > 0
            width: tl.btn
            height: tl.btn
            radius: Theme.groups ? Math.min(width / 2, Theme.rFull) : Theme.rSm
            color: moreHover.hovered || tl.menuId === -2 ? Theme.containerHigh : "transparent"
            Accessible.role: Accessible.Button
            Accessible.name: I18n.tr("tasks.a11y.more").replace("{n}", tl.moreN)
            Text {
                anchors.centerIn: parent
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("tasks.more").replace("{n}", tl.moreN)
            }
            HoverHandler { id: moreHover }
            TapHandler { onTapped: tl.openMenu(more, -2) }
        }
    }

    // The drag's ghost: the window's icon under the pointer.
    AppIcon {
        visible: tl.dragId >= 0
        z: 10
        width: tl.btn - 4
        height: width
        x: tl.ghostAt.x - width / 2
        y: tl.ghostAt.y - height / 2
        opacity: 0.9
        appId: tl.dragId >= 0 && tl.byId[tl.dragId] ? String(tl.byId[tl.dragId].app_id || "") : ""
        entry: tl.entryOf(appId)
    }

    // ---- the peek: beside the button, click-through, made only while shown ----
    LazyLoader {
        active: (tl.peekId >= 0 && tl.peekTile !== null) || (tl.dragId >= 0 && tl.dragWs >= 0)
        PopupWindow {
            id: peek
            readonly property bool moving: tl.dragId >= 0
            readonly property var tile: moving ? tl.dragTile : tl.peekTile
            readonly property var w: tl.byId[moving ? tl.dragId : tl.peekId] || null
            anchor.item: tile
            anchor.edges: tl.edge === "top" ? Edges.Bottom : (tl.edge === "bottom" ? Edges.Top : (tl.edge === "left" ? Edges.Right : Edges.Left))
            anchor.gravity: anchor.edges
            anchor.margins.top: tl.edge === "top" ? 8 : 0
            anchor.margins.bottom: tl.edge === "bottom" ? 8 : 0
            anchor.margins.left: tl.edge === "left" ? 8 : 0
            anchor.margins.right: tl.edge === "right" ? 8 : 0
            visible: tile !== null
            implicitWidth: box.width
            implicitHeight: box.height
            color: "transparent"
            mask: Region {}
            // Glass: blurred as the bar's sheet is (I296).
            BackgroundEffect.blurRegion: Region { item: Theme.blur ? box : null; radius: Theme.rSm }
            Rectangle {
                id: box
                width: Math.min(380, Math.max(titleT.implicitWidth, appT.implicitWidth) + 2 * Theme.gap)
                height: col.implicitHeight + Theme.gap
                radius: Theme.rSm
                color: Theme.panel
                border.width: 1
                border.color: Theme.outline
                Column {
                    id: col
                    x: Theme.gap
                    y: Theme.gap / 2
                    width: box.width - 2 * Theme.gap
                    Text {
                        id: titleT
                        width: parent.width
                        elide: Text.ElideRight
                        color: peek.moving ? Theme.accent : Theme.fg
                        font.pixelSize: Theme.fsCaption + 1
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: peek.moving ? I18n.tr("tasks.peek.move").replace("{n}", tl.dragIdx)
                            : (tl.peekState === "ok" ? tl.peekTitle
                                : (tl.peekState === "gone" ? I18n.tr("tasks.error.gone")
                                    : (tl.peekState === "none" ? I18n.tr("tasks.peek.untitled") : I18n.tr("tasks.peek.loading"))))
                    }
                    Text {
                        id: appT
                        visible: !peek.moving
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: peek.w ? tl.nameOf(peek.w) : ""
                    }
                }
            }
        }
    }

    // ---- the menu: an overlay over the output while open, so a press outside closes it and the keyboard reaches it
    // (a popup of a layer surface without keyboard gets none — measured for the dock, K51). Made on open, gone on close.
    LazyLoader {
        active: tl.menuOpen
        PanelWindow {
            id: menu
            screen: tl.screen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "kurashi-tasks-menu"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            // Glass: behind the menu's block, without its shadow (I296).
            BackgroundEffect.blurRegion: Region {
                x: Theme.blur ? menuBody.x : 0
                y: menuBody.y
                width: Theme.blur ? menuBody.width : 0
                height: Theme.blur ? menuBody.height - Theme.shadowDy : 0
                radius: Theme.rLg
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: function (ev) {
                    var inside = ev.x >= menuBody.x && ev.x < menuBody.x + menuBody.width
                        && ev.y >= menuBody.y && ev.y < menuBody.y + menuBody.height
                    if (inside) ev.accepted = false
                    else tl.closeMenu()
                }
            }
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: function (ev) { ev.accepted = tl.menuKeyPress(ev.key) }
            }
            Block {
                id: menuBody
                readonly property rect at: tl.menuAt
                x: tl.vertical ? (tl.edge === "left" ? at.x + at.width + Theme.gap : at.x - Theme.gap - width)
                    : Math.max(Theme.gap, Math.min(menu.width - width - Theme.gap, at.x + at.width / 2 - width / 2))
                y: tl.vertical ? Math.max(Theme.gap, Math.min(menu.height - height - Theme.gap, at.y + at.height / 2 - height / 2))
                    : (tl.edge === "bottom" ? at.y - Theme.gap - height : at.y + at.height + Theme.gap)
                width: Math.min(360, Math.max(200, col2.implicitWidth + 2 * Theme.gap + 2 * inset))
                height: col2.implicitHeight + 2 * Theme.gap + 2 * inset + Theme.shadowDy
                radius: Theme.rLg
                fill: Theme.panel
                flatBorder: Theme.outline
                softScale: 0.6
                Column {
                    id: col2
                    x: Theme.gap
                    y: Theme.gap
                    width: menuBody.width - 2 * Theme.gap - 2 * menuBody.inset
                    // The window's title (fetched on open) and its app; for "+N" the count.
                    Text {
                        width: parent.width
                        leftPadding: Theme.gap
                        text: tl.menuId === -2 ? I18n.tr("tasks.a11y.more").replace("{n}", tl.moreN)
                            : (tl.menuTitle !== "" ? tl.menuTitle : I18n.tr("tasks.peek.loading"))
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fsCaption
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Text {
                        visible: tl.menuId >= 0
                        width: parent.width
                        leftPadding: Theme.gap
                        bottomPadding: Theme.xs
                        text: tl.byId[tl.menuId] ? tl.nameOf(tl.byId[tl.menuId]) : ""
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                    }
                    Repeater {
                        model: tl.menuRows
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            width: col2.width
                            height: Theme.controlH
                            radius: Theme.rSm
                            color: (rowHover.hovered || tl.menuCurrent === index) && modelData.on ? Theme.containerHigh : "transparent"
                            opacity: modelData.on ? 1 : 0.5
                            Accessible.role: Accessible.MenuItem
                            Accessible.name: modelData.text
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.gap
                                width: parent.width - 2 * Theme.gap
                                elide: Text.ElideRight
                                text: row.modelData.text
                                color: Theme.fg
                                font.pixelSize: Theme.fs
                                font.family: Theme.fam(text, Theme.families)
                            }
                            HoverHandler { id: rowHover; onHoveredChanged: if (hovered) tl.menuCurrent = row.index }
                            TapHandler { enabled: row.modelData.on; onTapped: row.modelData.run() }
                        }
                    }
                    // Why the last action did not take (Shōjiki: nothing changed).
                    Text {
                        visible: tl.menuError !== ""
                        width: parent.width
                        leftPadding: Theme.gap
                        topPadding: Theme.xs
                        wrapMode: Text.Wrap
                        text: tl.menuError
                        color: Theme.error
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                    }
                }
            }
        }
    }

    // Test only (KURASHI_TASKS_LOG=1, frontend/test-tasks.sh): each button's box in its window and the icon it draws,
    // logged a moment after a change: "tasks-geom <output> <edge> <id>@<x>,<y>,<size>,<kind>,<urgent> … more@<x>,<y>,<n>
    // ws<id>@<x>,<y>,<w>,<h> …" (the chips, for a drag).
    // Without the variable: no timer, no log.
    Timer {
        id: logTimer
        interval: 300
        onTriggered: {
            var parts = ["tasks-geom", tl.outName, tl.edge]
            for (var i = 0; i < rep.count; i++) {
                var it = rep.itemAt(i)
                if (!it) continue
                var p = it.mapToItem(null, 0, 0)
                parts.push(it.modelData + "@" + Math.round(p.x) + "," + Math.round(p.y) + "," + Math.round(it.width)
                    + "," + it.iconKind + "," + (it.urgent ? 1 : 0))
            }
            if (tl.moreN > 0) {
                var q = more.mapToItem(null, 0, 0)
                parts.push("more@" + Math.round(q.x) + "," + Math.round(q.y) + "," + tl.moreN)
            }
            var bx = tl.pillBoxes()
            for (var k = 0; k < bx.length; k++)
                parts.push("ws" + bx[k].id + "@" + bx[k].x + "," + bx[k].y + "," + bx[k].w + "," + bx[k].h)
            console.log(parts.join(" "))
        }
    }
    function requestLog() { if (logOn) logTimer.restart() }
    onXChanged: requestLog()
    onYChanged: requestLog()
}
