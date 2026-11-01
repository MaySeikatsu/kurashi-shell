import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../components"
import "../components/launcher"
import "../components/island"
import "../components/decor"

// Launcher (M5): centred overlay with exclusive keyboard focus while open. The daemon owns the
// open state (runtime.ui.launcher), the index, ranking and launching; this only renders results
// of `query launcher` and sends `launcher.launch` / `ui.close`.
//
// Prefix modes (K44, I126, W26; docs/ux/launcher.md): `:` emoji as a grid (8 a row, arrows move in two dimensions,
// recent first), `;` the clipboard history (image thumbnails, pins, Shift+Delete removes, a "clear history" row with a
// confirm), `>` commands, `?` the keybind cheat sheet (also action `launcher.keys`: `runtime.ui.launcher_query`).
//
// Same idle discipline as Stage (K16): permanently mapped but transparent, input-less and
// focus-less while hidden, so it renders 0 frames. Typing never animates: the result list is replaced, the highlight
// just moves.
//
// W34 (docs/ux/motion.md): under a top or bottom bar the launcher grows out of the island pill as one shape (BarMorph:
// the island's MorphShape, two springs, the liquid neck at the bar's edge, the pill's face in its head) and folds back
// into it; the card then hangs under the bar's centre and the window covers the bar's strip above it (margin 0, the
// shape's box; K16: its size only, never the output's). Without one (a side bar, no bar) it stays centred on the output
// and slides in, as before.
PanelWindow {
    id: lp

    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool want: ui.launcher === true
    // The text `launcher.keys` (or a later caller) opens the launcher with; "" for a plain open.
    readonly property string openQuery: ui.launcher_query || ""
    readonly property string mode: {
        var c = field.text.charAt(0)
        return c === ":" ? "emoji" : (c === ";" ? "clip" : (c === "?" ? "keys" : "apps"))
    }
    // K59: this window's tile set, shared by its reliefs, and the pointer light's sensor. K61: the card's carry while it
    // slides in (`texture.sheet = carried`; its scale is not carried); 0 in the morph, whose shape carries its own.
    property var tileSheet: tilesLoader.item
    readonly property point sheetCarry: morph.carry
    Loader { id: tilesLoader; active: Theme.texOn && Theme.texTilePx > 0; sourceComponent: TileSheet {} }
    LightSense {}
    readonly property int rowH: 48
    readonly property int maxRows: 7
    readonly property int cols: 8          // emoji grid
    readonly property int cellH: 60
    readonly property int gridRows: 5
    // The list follows its results: as tall as its rows, within one row and the mode's most.
    readonly property int maxListH: mode === "keys" ? 432 : (mode === "clip" ? 396 : maxRows * rowH)
    readonly property int contentH: {
        var h = 0
        for (var i = 0; i < results.length && h < maxListH; i++) h += heightOf(results[i])
        return h
    }
    readonly property int listH: sysMenu ? sysH : startGrid ? startH : mode === "emoji"
        ? Math.max(1, Math.min(Math.ceil(results.length / cols), gridRows)) * cellH
        : Math.max(rowH, Math.min(contentH, maxListH))
    readonly property bool footer: mode !== "apps"
    readonly property bool shown: morph.shown
    property var results: []
    property int sel: 0
    property string err: ""     // translated failure line above the list; "" when there is none
    property bool confirmClear: false   // the "clear history" row asked once; Enter again clears
    // Clipboard thumbnails asked for during this open (id → path, "!" = none), and which ids were asked.
    property var thumbs: ({})
    property var asked: ({})
    property var scr: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null   // latched on open so the card never jumps outputs

    // ---- W53 (K80 Decided 10, contract row 563): the start-menu skin. While the look dresses a start button (`decor.start`,
    // data: no name is compared, rule 4) the launcher is its start menu: it hangs from the start button (IslandGeom's
    // `start` origin, latched on open; the bar's start end without one), the rows over a footer with the session's keys,
    // in the look's chrome — or in the dress's own skin (StartBase `menu`, contract start/StartMenuBase.qml) where it
    // brings one. Every other look: today's launcher, unchanged.
    readonly property bool skin: Theme.slot("start") !== ""
    // The dress, made only while the menu is open, for its skin's url (it is not shown here).
    StartHost { id: dressOf; visible: false; active: has && lp.skin && lp.want }
    readonly property url skinUrl: dressOf.ready ? dressOf.item.menu : ""
    property var startAt: null
    readonly property string skinEdge: startAt && startAt.edge === "top" ? "top"
        : (startAt ? "bottom" : (bars.atTop ? "top" : "bottom"))
    // The band on the menu's side: the dress's skin keeps its own; the launcher's own start menu draws the start button's
    // label up a band in the caption's fill where the look shows that label (98's banner) — data only, rule 4.
    readonly property bool ownBanner: skin && !skinPart.ready && Theme.decor("start.label", false) === true
    readonly property real skinBand: skin && skinPart.ready ? skinPart.item.bandW : (ownBanner ? 24 : 0)
    readonly property real skinHeader: skin && skinPart.ready ? skinPart.item.headerH : 0
    readonly property real skinFooter: skin && !sysMenu ? Math.max(Theme.controlH + 2 * Theme.gap, skinPart.ready ? skinPart.item.footerH : 0) : 0
    // W53.3 (`[decor] start.grid`, columns; 0 = rows): the start menu's empty field shows the apps as a grid of icons with
    // their names (11's Start) — the dock's pinned apps where there are any ("Pinned"), else the most used ("Apps") — and
    // under it the most used of the rest in two columns ("Recommended"). Typing gives the ranked rows, as before.
    readonly property int startCols: skin ? Math.max(0, Theme.decor("start.grid", 0)) : 0
    readonly property bool startGrid: startCols > 0 && mode === "apps" && field.text === "" && field.preeditText === ""
    readonly property int startRows: 3
    readonly property int startCellH: 84
    readonly property int recRowH: 52
    readonly property int recCount: 6
    readonly property int headH: 32
    readonly property var pinnedIds: {
        var p = bars.valueOf("dock.pinned", [])
        return Array.isArray(p) ? p.filter(function (s) { return typeof s === "string" && s !== "" })
                                   .map(function (s) { return s.replace(/\.desktop$/, "") }) : []
    }
    function appKey(r) { return String(r.id || "").replace(/\.desktop$/, "") }
    readonly property var startApps: results.filter(function (r) { return r.kind === "app" })
    readonly property var startPinned: {
        var out = []
        for (var i = 0; i < pinnedIds.length; i++)
            for (var j = 0; j < startApps.length; j++)
                if (appKey(startApps[j]) === pinnedIds[i]) { out.push(startApps[j]); break }
        return out
    }
    readonly property bool hasPins: startPinned.length > 0
    readonly property var startTop: (hasPins ? startPinned : startApps).slice(0, startCols * startRows)
    readonly property var startRec: startApps.filter(function (r) { return lp.startTop.indexOf(r) < 0 }).slice(0, recCount)
    // One flat selection over both parts: the grid's cells, then the recommended rows.
    readonly property var startItems: startTop.concat(startRec)
    readonly property int startH: headH + Math.max(1, Math.ceil(startTop.length / Math.max(1, startCols))) * startCellH
        + (startRec.length > 0 ? Theme.gap * 2 + headH + Math.ceil(startRec.length / 2) * recRowH : 0)
    // Up, down, left, right over the grid (`startCols` a row) and the recommended rows (two a row).
    function startMove(dx, dy) {
        var n = startItems.length, t = startTop.length
        if (n === 0) return
        var i = Math.max(0, Math.min(sel, n - 1))
        if (dx !== 0) { sel = Math.max(0, Math.min(n - 1, i + dx)); return }
        var j = i
        if (i < t) {
            j = i + dy * startCols
            if (j >= t) j = n > t ? t + ((i % startCols) >= startCols / 2 && n > t + 1 ? 1 : 0) : i
            if (j < 0) j = i
        } else {
            j = i + dy * 2
            if (j < t) j = t > 0 ? Math.min(t - 1, Math.floor((t - 1) / startCols) * startCols
                                                     + ((i - t) % 2 === 1 ? Math.floor(startCols / 2) : 0)) : i
            if (j >= n) j = i
        }
        sel = j
    }
    readonly property int skinW: startCols > 0 ? 640 : 420
    // W53.4 (`[decor] start.form = menu`, lead review): the start menu on an empty field is the system's menu — Mac OS X's
    // Apple menu — as menu rows in the look's menu style: System Settings…, the recent apps, Sleep, Restart…, Shut Down…,
    // Lock Screen, Log Out…; the arrows move, Return runs a row, a row ending in "…" asks again first (the session
    // menu's own confirm words), Esc steps back. Typing turns it into the search (Spotlight's way). Rows only for what
    // acts (Shōjiki): no About (no page says it), no Force Quit (no intent).
    readonly property bool sysMenu: skin && Theme.decor("start.form", "search") === "menu" && mode === "apps"
        && field.text === "" && field.preeditText === ""
    property int sysSel: 0
    property int armed: -1
    readonly property string userName: String(Quickshell.env("USER") || "")
    readonly property var sysRows: {
        var r = [{ act: "settings.open", label: I18n.tr("startmenu.settings") }, { sep: true }]
        var apps = startApps.slice(0, 5)
        if (apps.length > 0) {
            r.push({ head: I18n.tr("startmenu.recent") })
            for (var i = 0; i < apps.length; i++) r.push({ app: apps[i], label: apps[i].name || apps[i].id })
            r.push({ sep: true })
        }
        r.push({ act: "session.suspend", label: I18n.tr("startmenu.sleep") })
        r.push({ act: "session.reboot", label: I18n.tr("startmenu.restart"), confirm: "frontend.session.confirm.reboot" })
        r.push({ act: "session.poweroff", label: I18n.tr("startmenu.shutdown"), confirm: "frontend.session.confirm.poweroff" })
        r.push({ sep: true })
        r.push({ act: "session.lock", label: I18n.tr("startmenu.lock") })
        r.push({ act: "session.logout", label: I18n.tr("startmenu.logout").replace("{user}", userName),
                 confirm: "frontend.session.confirm.logout" })
        return r
    }
    readonly property int sysRowH: ms.rowH(26)
    function sysRowHeight(r) { return r.sep ? 9 : (r.head ? 22 : sysRowH) }
    readonly property int sysH: {
        var h = 0
        for (var i = 0; i < sysRows.length; i++) h += sysRowHeight(sysRows[i])
        return h
    }
    function sysPick(i) { return i >= 0 && i < sysRows.length && (sysRows[i].act !== undefined || sysRows[i].app !== undefined) }
    function sysMove(d) {
        var j = sysSel + d
        while (j >= 0 && j < sysRows.length && !sysPick(j)) j += d
        if (sysPick(j)) { sysSel = j; armed = -1 }
    }
    function sysRun(i) {
        if (!sysPick(i)) return
        var r = sysRows[i]
        if (r.app) { sel = startApps.indexOf(r.app); var id = r.app.id
            Store.act("launcher.launch", { id: id }, function (done, e) { if (e) lp.err = lp.errorText(e); else Store.act("ui.close") })
            return }
        if (r.confirm && armed !== i) { armed = i; return }
        armed = -1
        var act = r.act
        // The launcher closes first: the lock, the session and Settings take the keyboard.
        Store.act("ui.close", {}, function () { Store.act(act, {}) })
    }
    onSysMenuChanged: { sysSel = 0; armed = -1 }
    // The look's menu rows (row 591): its highlight's shape and corner, its part under each row.
    MenuStyle { id: ms }

    function heightOf(r) {
        switch (r.kind) {
        case "keygroup": return 30
        case "key": return 38
        case "clip": return r.image ? 72 : 58
        default: return rowH
        }
    }
    function focusedScreen() {
        var o = (Store.docs["svc.workspaces"] && Store.docs["svc.workspaces"].outputs) || {}
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) {
            var l = o[s[i].name] || []
            for (var j = 0; j < l.length; j++)
                if (l[j].focused) return s[i]
        }
        return s.length > 0 ? s[0] : null
    }
    // A failure carries a kind (invalid, unavailable, internal, or the Store's own) and a message. A message that is
    // one of our i18n keys (the clipboard's refusals) is shown translated; any other message is English and never
    // shown: the kind picks a translated line, unknown kinds the generic one.
    function errorText(e) {
        if (e.msg) {
            var m = I18n.tr(e.msg)
            if (m !== e.msg) return m
        }
        var k = "surfaces.launcher.error." + (e.kind || "failed")
        var t = I18n.tr(k)
        return t !== k ? t : I18n.tr("surfaces.launcher.error.failed")
    }
    function selectable(i) { return i >= 0 && i < results.length && results[i].kind !== "keygroup" }
    // The first selectable row from `i` going `d` (±1), else the other way, else 0.
    function settle(i, d) {
        var j = i
        while (j >= 0 && j < results.length && !selectable(j)) j += d
        if (selectable(j)) return j
        j = i
        while (j >= 0 && j < results.length && !selectable(j)) j -= d
        return selectable(j) ? j : 0
    }
    function move(d) {
        if (results.length === 0) return
        if (mode === "emoji") {
            var g = sel + d
            if (g >= 0 && g < results.length) sel = g
            else if (d > 1) sel = results.length - 1     // Down on the last row: the last cell
            return
        }
        var j = sel + d
        while (j >= 0 && j < results.length && !selectable(j)) j += d > 0 ? 1 : -1
        if (selectable(j)) sel = j
    }
    function run(q, keep) {
        Store.query("launcher", q, function (items, e) {
            if (!lp.want) return
            var old = lp.sel
            lp.results = items || []
            lp.sel = lp.settle(keep ? Math.min(old, lp.results.length - 1) : 0, 1)
            lp.err = e ? lp.errorText(e) : ""
        })
    }
    function requestThumb(id) {
        if (!want || asked[id]) return
        asked[id] = true
        Store.act("launcher.clip.thumb", { id: id }, function (done, e) {
            if (!lp.want) return
            var t = Object.assign({}, lp.thumbs)
            t[id] = done && done.data && done.data.path ? done.data.path : "!"
            lp.thumbs = t
        })
    }
    // Clipboard keys: Shift+Delete removes the selected entry (a pin: unpins it), Ctrl+P pins or unpins it.
    function clipAct(action) {
        var r = results[sel]
        if (!r || r.kind !== "clip") return
        Store.act(action, { id: r.id }, function (done, e) {
            if (e) { lp.err = lp.errorText(e); return }
            lp.err = ""
            lp.run(field.text, true)
        })
    }
    function launch() {
        var items = startGrid ? startItems : results
        if (sel < 0 || sel >= items.length) return
        var r = items[sel]
        if (r.kind === "clipclear") {
            if (!confirmClear) { confirmClear = true; return }
            confirmClear = false
            Store.act("launcher.clip.clear", {}, function (done, e) {
                if (e) { lp.err = lp.errorText(e); return }
                lp.run(field.text)
            })
            return
        }
        if (!r.id) return
        var id = r.id
        // A `>` command may open a panel of its own (quick settings, the session keys): the launcher closes first. So does
        // a Settings link (`settings:<page>`, row 387): Settings is a window of its own.
        if (id.indexOf("cmd:") === 0 || id.indexOf("settings:") === 0) {
            Store.act("ui.close", {}, function () { Store.act("launcher.launch", { id: id }) })
            return
        }
        Store.act("launcher.launch", { id: id }, function (done, e) {
            // Close only once the app is up: a failure stays open with its reason.
            if (e) { lp.err = lp.errorText(e); return }
            Store.act("ui.close")
        })
    }
    onSelChanged: confirmClear = false
    onModeChanged: confirmClear = false

    screen: scr
    BarConfig { id: bars; screen: lp.scr }
    // While the shape is out under a top or bottom bar, one vertical edge anchored (the compositor centres the surface
    // horizontally, so the shape's box is centred on the bar); none otherwise (idle, or no such bar): centred on the output.
    // The start menu: its corner at the start button (the window's shade round the card counted), off its bar.
    anchors {
        top: skin ? skinEdge === "top" : morph.layout && !bars.atBottom
        bottom: skin ? skinEdge !== "top" : morph.layout && bars.atBottom
        left: skin
    }
    // (`[decor] start.menu = center`, W53.3: the menu stands centred over the output, as 11's Start over its centred taskbar.)
    margins.left: skin ? Math.max(0, Math.min((scr ? scr.width : 1920) - implicitWidth,
        Theme.decor("start.menu", "button") === "center" ? Math.round(((scr ? scr.width : 1920) - implicitWidth) / 2)
            : (startAt ? startAt.x : Theme.pad) - morph.shade)) : 0
    // (W53.4: a start menu that hangs from its bar, `[decor] flyout.hang` — Mac OS X's menus — meets it, no gap)
    readonly property int hangGap: Theme.decor("flyout.hang", false) === true ? 0 : Theme.gap
    margins.top: skin && skinEdge === "top" ? Math.max(0, (startAt ? startAt.y + startAt.h + hangGap : bars.topInset) - morph.shade) : 0
    margins.bottom: skin && skinEdge !== "top"
        ? Math.max(0, (startAt && scr ? scr.height - startAt.y + hangGap : bars.bottomInset) - morph.shade) : 0
    implicitWidth: morph.width
    implicitHeight: morph.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: want ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "kurashi-launcher"
    color: "transparent"
    mask: shown ? cardRegion : emptyRegion
    // Behind the shape as drawn, every frame of its morph (I295, I296; BarMorph's blur box).
    BackgroundEffect.blurRegion: Theme.blur && morph.blurOn ? blurRegion : emptyRegion
    Region { id: cardRegion; item: morph.cardItem }
    // (rounded as the card is drawn: a square region showed the blur past its corners, I276)
    Region {
        id: blurRegion
        x: morph.x + morph.blurX
        y: morph.y + morph.blurY
        width: morph.blurW
        height: morph.blurH
        topLeftRadius: morph.blurRTop
        topRightRadius: morph.blurRTop
        bottomLeftRadius: morph.blurRBottom
        bottomRightRadius: morph.blurRBottom
    }
    Region { id: emptyRegion }

    onWantChanged: {
        if (want) {
            scr = focusedScreen()
            startAt = skin && scr ? IslandGeom.rectOf(scr.name, "start") : null
            results = []; sel = 0; err = ""; confirmClear = false
            thumbs = ({}); asked = ({})
            // Setting the text runs its query (onTextChanged); an unchanged text needs the run here.
            if (field.text === openQuery) run(openQuery)
            else field.text = openQuery
            field.cursorPosition = field.text.length
            field.forceActiveFocus()
        } else {
            // Ma: a focused field keeps its cursor blinking, and the hidden window drew twice a second for it (before W34
            // too): the field lets go of the focus when the launcher closes.
            field.focus = false
        }
    }
    // `launcher.keys` while the launcher is already open: switch to the cheat sheet.
    onOpenQueryChanged: if (want && openQuery !== "" && field.text !== openQuery) {
        field.text = openQuery
        field.cursorPosition = field.text.length
    }
    BarMorph {
        id: morph
        outName: lp.scr ? lp.scr.name : ""
        onBar: !lp.skin && (bars.atTop || bars.atBottom)
        flip: lp.skin ? lp.skinEdge !== "top" : bars.atBottom
        open: lp.want
        cardW: card.width
        cardH: card.height
        slide: 12
        slideScale: 0.96
        onHidden: { lp.results = []; lp.thumbs = ({}) }

        // The card's content. In the morph the shape is its chrome; sliding in, it is a Block (K42, K45): a flat panel with a
        // hairline, a keycap panel with an ink outline and hard shadow, a soft glass panel with a rim and a drop shadow, or a
        // panel outlined in ink (line).
        Item {
            id: card
            width: lp.skin ? lp.skinW + lp.skinBand : 600
            readonly property real inset: Theme.outlineW + Theme.ringW
            readonly property int footH: lp.footer ? Theme.gap + 18 : 0
            // Where the content stands: the start-menu skin keeps a band on the left and a header on top (0 otherwise).
            readonly property real l0: Theme.pad + inset + lp.skinBand
            readonly property real t0: Theme.pad + inset + lp.skinHeader
            readonly property real w0: width - l0 - Theme.pad - inset
            // (a system menu keeps a menu's 4 px above and below its rows, not the search's padding)
            height: (lp.sysMenu ? 8 : 2 * Theme.pad) + 2 * inset + (lp.sysMenu ? 0 : 44 + Theme.gap) + (lp.err !== "" ? errRow.height + Theme.gap : 0) + lp.listH
                + footH + lp.skinHeader + lp.skinFooter + (morph.morph ? 0 : Theme.shadowDy)
            // W57 (K78): the launcher stands highest (level 4).
            Elevation {
                visible: !morph.morph
                anchors.fill: parent
                anchors.bottomMargin: Theme.shadowDy
                radius: Theme.rLg + 4
                level: 4
            }
            Block {
                visible: !morph.morph && !skinPart.ready
                anchors.fill: parent
                radius: Theme.rLg + 4
                fill: Theme.panel
                flatBorder: Theme.outline
                // K62: the pen's salt for the card's outline (a surface knows who it is; its place moves as it opens).
                penSeed: 0x1A0C
            }
            // The dress's start-menu skin in place of the Block (row 563).
            Loader {
                id: skinPart
                readonly property bool ready: status === Loader.Ready && item !== null
                anchors.fill: parent
                anchors.bottomMargin: Theme.shadowDy
                active: lp.skin && lp.skinUrl !== ""
                source: active ? lp.skinUrl : ""
                onLoaded: {
                    item.label = Qt.binding(function () { return Theme.decor("start.label", false) ? I18n.tr("decor.start.label") : "" })
                    item.open = Qt.binding(function () { return lp.want })
                    item.edge = Qt.binding(function () { return lp.skinEdge })
                }
            }

            // The launcher's own start-menu banner (`ownBanner`): the caption's fill run up the side (`title.fill`, its
            // second role at the top), the start label rotated up from the bottom, bold in the caption's ink.
            Loader {
                active: lp.ownBanner
                x: card.inset + Theme.crisp(2 * Math.max(1, Theme.bevelW), Screen.devicePixelRatio) + 1
                y: x
                width: lp.skinBand - 2
                height: card.height - (morph.morph ? 0 : Theme.shadowDy) - 2 * y
                sourceComponent: Item {
                    id: banner
                    readonly property var fills: Theme.decor("title.fill", [])
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0; color: banner.fills.length > 1 ? banner.fills[1] : Theme.accent }
                            GradientStop { position: 1; color: banner.fills.length > 0 ? banner.fills[0] : Theme.accent }
                        }
                    }
                    PixelLabel {
                        width: implicitWidth
                        height: parent.width
                        rotation: -90
                        transformOrigin: Item.TopLeft
                        x: 0
                        y: parent.height - 6
                        text: I18n.tr("decor.start.label")
                        color: Theme.decor("title.on", "") !== "" ? Theme.decor("title.on", "") : Theme.fgOnAccent
                        pixelSize: Theme.fsTitle + 2
                        weight: Theme.wBold
                    }
                }
            }

            Block {
                id: box
                x: card.l0
                y: card.t0
                width: card.w0
                // (the system menu keeps the field, focused and typing, out of sight: 0 px tall until the first key)
                height: lp.sysMenu ? 0 : 44
                opacity: lp.sysMenu ? 0 : 1
                radius: Theme.rFull
                ringScale: 0
                softScale: 0
                // W53.5 (`[decor] field.form = underline`): the field is a line under the query — an RPG's name-entry line
                // (whole grid pixels, a block cursor), the PS2's glowing underline — with no box, frame or well.
                readonly property bool underline: Theme.decor("field.form", "box") === "underline"
                framed: !underline
                // A text field is a well (row 591): sunken under a bevel chrome, nothing otherwise.
                sunken: !underline
                fill: underline ? "transparent" : Theme.surface
                flatBorder: underline ? "transparent" : (field.activeFocus ? Theme.accent : Theme.outline)
                penSeed: 0x1A0D
                FieldLine {
                    visible: box.underline
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 8; rightMargin: 8 }
                    focused: field.activeFocus
                }
                Icon {
                    id: searchIcon
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    name: lp.mode === "emoji" ? "mood" : (lp.mode === "clip" ? "content_paste"
                        : (lp.mode === "keys" ? "keyboard" : "search"))
                    glyph: "⌕"
                    color: Theme.dim
                    size: Theme.fsTitle + 4
                }
                TextInput {
                    id: field
                    anchors { fill: parent; leftMargin: searchIcon.x + searchIcon.width + 8; rightMargin: 14 }
                    // The name-entry line's block cursor on a pixel grid (a whole character cell), else the caret.
                    // W53.8: the look's caret (`field.caret`, `field.blink`: a terminal's block that stops blinking).
                    cursorDelegate: box.underline && Theme.pixelType ? blockCaret
                        : (Theme.decor("field.caret", "bar") !== "bar" || Theme.decor("field.blink", -1) >= 0 ? lookCaret : null)
                    Component { id: lookCaret; Caret { ground: box.underline ? Theme.surface : box.fill } }
                    Component {
                        id: blockCaret
                        Rectangle {
                            width: Math.round(field.font.pixelSize * 0.75)
                            height: field.font.pixelSize
                            y: Math.round((field.height - height) / 2)
                            antialiasing: false
                            color: Theme.fg
                            visible: field.cursorVisible
                        }
                    }
                    color: Theme.fg
                    font.pixelSize: Theme.fsTitle
                    font.weight: Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    clip: true
                    onTextChanged: if (lp.want) lp.run(text)
                    Keys.onEscapePressed: {
                        if (lp.confirmClear) lp.confirmClear = false
                        else if (lp.armed >= 0) lp.armed = -1
                        else Store.act("ui.close")
                    }
                    Keys.onDownPressed: lp.sysMenu ? lp.sysMove(1) : lp.startGrid ? lp.startMove(0, 1) : lp.move(lp.mode === "emoji" ? lp.cols : 1)
                    Keys.onUpPressed: lp.sysMenu ? lp.sysMove(-1) : lp.startGrid ? lp.startMove(0, -1) : lp.move(lp.mode === "emoji" ? -lp.cols : -1)
                    // In the emoji grid (and the start menu's) the arrows move across a row; elsewhere the text cursor.
                    Keys.onLeftPressed: (event) => {
                        if (lp.startGrid) lp.startMove(-1, 0)
                        else if (lp.mode === "emoji") lp.move(-1)
                        else event.accepted = false
                    }
                    Keys.onRightPressed: (event) => {
                        if (lp.startGrid) lp.startMove(1, 0)
                        else if (lp.mode === "emoji") lp.move(1)
                        else event.accepted = false
                    }
                    Keys.onReturnPressed: lp.sysMenu ? lp.sysRun(lp.sysSel) : lp.launch()
                    Keys.onEnterPressed: lp.sysMenu ? lp.sysRun(lp.sysSel) : lp.launch()
                    Keys.onPressed: (event) => {
                        var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                        if (lp.mode === "clip" && event.key === Qt.Key_Delete && shift) {
                            lp.clipAct("launcher.clip.delete"); event.accepted = true
                        } else if (lp.mode === "clip" && event.key === Qt.Key_P && ctrl) {
                            lp.clipAct("launcher.clip.pin"); event.accepted = true
                        } else if (event.key === Qt.Key_PageDown) {
                            lp.move(lp.mode === "emoji" ? lp.cols * lp.gridRows : 8); event.accepted = true
                        } else if (event.key === Qt.Key_PageUp) {
                            lp.move(lp.mode === "emoji" ? -lp.cols * lp.gridRows : -8); event.accepted = true
                        }
                    }
                    Text {
                        id: placeholder
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: field.text === "" && field.preeditText === ""
                        color: Theme.dim
                        font: field.font
                        text: I18n.tr("launcher.placeholder")
                    }
                    // The prefix modes, named while the field is empty.
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        // (not in the narrower start menu: the placeholder needs the room)
                        // (and only where it fits beside the placeholder: a wide pixel face leaves no room)
                        visible: field.text === "" && field.preeditText === "" && !lp.skin
                            && placeholder.contentWidth + implicitWidth + Theme.gap <= parent.width
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("launcher.modes")
                    }
                }
            }

            // Failure line above the results (a failed launch or query). The results stay usable.
            Text {
                id: errRow
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                visible: lp.err !== ""
                x: card.l0
                y: box.y + box.height + Theme.gap
                width: card.w0
                wrapMode: Text.WordWrap
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: lp.err
            }

            // The look's scroll bar over the list's end edge (W53.7/8: the `scroll` slot's host; nothing without a part).
            // The rows give way to it (its width and a gap), so no hint sits under the bar.
            ScrollHost {
                id: listBar
                z: 1
                flick: list
                visible: shown && list.visible
                x: card.l0 + card.w0 - width
                y: list.y
                stepPx: lp.rowH
            }
            ListView {
                id: list
                visible: lp.mode !== "emoji" && !lp.startGrid && !lp.sysMenu
                x: card.l0
                y: lp.err !== "" ? errRow.y + errRow.height + Theme.gap : box.y + box.height + (lp.sysMenu ? 0 : Theme.gap)
                width: card.w0 - (listBar.shown ? listBar.width + 4 : 0)
                height: lp.listH
                clip: true
                interactive: false
                // Only the rows on screen exist, so only their thumbnails are asked for (Ma).
                cacheBuffer: 0
                model: lp.mode !== "emoji" && !lp.startGrid ? lp.results : []
                currentIndex: lp.sel
                highlightMoveDuration: 0
                // The selected row's highlight is one tonal block that springs to the row (keycap: outlined).
                highlight: Block {
                    visible: !ms.has && ms.highlight === "capsule"
                    width: list.width
                    height: list.currentItem ? list.currentItem.height - 2 : lp.rowH - 2
                    radius: ms.radius(Theme.rLg)
                    ringScale: 0
                    softScale: 0
                    fill: Theme.selected
                    // K62: one line however far it springs (its place changes with the selection).
                    penSeed: 0x1A0E
                    Behavior on y {
                        enabled: lp.shown && Theme.springOn
                        NumberAnimation { duration: Theme.stdMs; easing.type: Easing.OutBack; easing.overshoot: Theme.overshoot * 0.6 }
                    }
                }
                highlightFollowsCurrentItem: true
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string kind: modelData.kind || ""
                    readonly property bool isCalc: kind === "calc"
                    // Prefix modes (daemon): `:` emoji, `;` clipboard; a `note` row only explains (an i18n key, no id).
                    readonly property bool isEmoji: kind === "emoji"
                    readonly property bool isNote: kind === "note"
                    // `>` commands (I126) carry their Material icon; the web row searches the query.
                    readonly property bool isCommand: kind === "command"
                    readonly property bool isWeb: kind === "web"
                    // Rows drawn by their own component (W26): a clipboard entry, the clear row, a cheat sheet row.
                    readonly property bool own: kind === "clip" || kind === "clipclear" || kind === "key" || kind === "keygroup"
                    readonly property bool copies: isCalc || isEmoji
                    readonly property bool selected: index === lp.sel
                    width: list.width
                    height: lp.heightOf(modelData)

                    // The look's row face (W53, row 591) where it leaves today's springing highlight.
                    MenuRowFace {
                        id: rowFace
                        anchors.fill: parent
                        anchors.bottomMargin: 2
                        highlighted: row.selected
                    }
                    Item {
                        anchors.fill: parent
                        visible: !row.own
                        Item {
                            id: ico
                            x: 10 + ms.lead; anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -Theme.shadowDy / 2
                            width: 30; height: 30
                            // Row 380 (I190): the file the daemon resolved from the icon theme, loaded asynchronously (off the GUI
                            // thread). Only a name it found no file for asks Qt's icon theme (~20 ms on the GUI thread per new name).
                            property string src: row.kind !== "app" ? ""
                                : (row.modelData.icon_path ? "file://" + row.modelData.icon_path
                                : (row.modelData.icon ? Quickshell.iconPath(row.modelData.icon, true) : ""))
                            Image {
                                id: img
                                anchors.fill: parent
                                source: ico.src
                                sourceSize: Qt.size(60, 60)
                                asynchronous: true
                                visible: ico.src !== "" && status === Image.Ready
                            }
                            // The app's picture: its relief on its own pixels, masked by its alpha (row 285), so a transparent row's
                            // ground does not halo. A fallback tile carries its own relief (below).
                            Loader {
                                active: Theme.texControls && img.visible && !!(Window.window && QsWindow.window && QsWindow.window.tileSheet)
                                anchors.fill: parent
                                sourceComponent: Item {
                                    anchors.fill: parent
                                    ShaderEffectSource {
                                        id: pictureMask
                                        width: parent.width
                                        height: parent.height
                                        sourceItem: img
                                        live: false
                                        x: -100000
                                        y: -100000
                                        readonly property var key: [img.status, img.source, img.width, img.height]
                                        onKeyChanged: scheduleUpdate()
                                        Component.onCompleted: scheduleUpdate()
                                    }
                                    Relief { anchors.fill: parent; radius: 0; mask: pictureMask }
                                }
                            }
                            // Text fallback: initial of the name; a calculation shows its icon.
                            Rectangle {
                                id: fallback
                                anchors.fill: parent
                                visible: !img.visible
                                radius: Theme.rSm
                                color: row.isCalc ? Theme.accent : (row.isEmoji ? "transparent" : Theme.surface)
                                border.width: !row.isEmoji ? Theme.outlineW : 0
                                border.color: Theme.outlineColor
                                Icon {
                                    anchors.centerIn: parent
                                    visible: row.isCalc || row.isNote || row.isCommand || row.isWeb
                                    name: row.isCalc ? "calculate"
                                        : ((row.isCommand || row.isWeb) ? (row.modelData.icon || "bolt") : "info")
                                    glyph: row.isCalc ? "=" : (row.isWeb ? "⌕" : (row.isCommand ? "›" : "i"))
                                    filled: true
                                    color: row.isCalc ? Theme.fgOnAccent : Theme.dim
                                }
                                Text {
                                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                    antialiasing: !Theme.pixelType
                                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                                    anchors.centerIn: parent
                                    visible: row.isEmoji
                                    font.pixelSize: 24
                                    text: row.modelData.glyph || ""
                                }
                                Text {
                                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                    antialiasing: !Theme.pixelType
                                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                                    anchors.centerIn: parent
                                    visible: row.kind === "app" || row.kind === "action"
                                    color: Theme.dim
                                    font.pixelSize: Theme.fs
                                    font.weight: Theme.wBold
                                    font.family: Theme.fam(text, Theme.families)
                                    text: (row.modelData.name || "?").charAt(0).toUpperCase()
                                }
                                // K61 (docs/ux/texture.md "Controls"): an opaque fallback tile carries the relief over its glyph,
                                // in a window that shares its sheet (Relief makes its own otherwise). A picture stays flat.
                                Loader {
                                    active: Theme.texControls && fallback.color.a >= 1 && !!(Window.window && QsWindow.window && QsWindow.window.tileSheet)
                                    anchors.fill: parent
                                    anchors.margins: fallback.border.width
                                    sourceComponent: Relief { anchors.fill: parent; radius: Math.max(0, fallback.radius - fallback.border.width) }
                                }
                            }
                        }
                        Column {
                            anchors { left: ico.right; leftMargin: Theme.gap + 2; right: hint.left; rightMargin: 8
                                      verticalCenter: ico.verticalCenter }
                            Text {
                                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                antialiasing: !Theme.pixelType
                                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                                width: parent.width
                                elide: Text.ElideRight
                                wrapMode: row.isNote ? Text.Wrap : Text.NoWrap
                                maximumLineCount: 2
                                color: rowFace.ink(row.selected ? Theme.fgOnSelected : Theme.fg)
                                font.pixelSize: row.isCalc ? Theme.fsTitle + 2 : (row.isNote ? Theme.fs - 1 : Theme.fs)
                                font.weight: row.isCalc || row.selected ? Theme.wBold : Theme.wMedium
                                font.family: Theme.fam(text, Theme.families)
                                text: row.isNote ? I18n.tr(row.modelData.name).replace("{path}", row.modelData.arg || "")
                                    : (row.isWeb ? I18n.tr("launcher.web").replace("{q}", row.modelData.name) : row.modelData.name)
                            }
                            Text {
                                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                antialiasing: !Theme.pixelType
                                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                                width: parent.width
                                visible: !!row.modelData.generic
                                elide: Text.ElideRight
                                color: rowFace.ink(Theme.dim)
                                font.pixelSize: Theme.fs - 2
                                font.family: Theme.fam(text, Theme.families)
                                text: row.modelData.generic || ""
                            }
                        }
                        // What Enter does on the selected row: launch, or copy a calculation.
                        Text {
                            id: hint
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            antialiasing: !Theme.pixelType
                            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: ico.verticalCenter }
                            visible: row.selected && !row.isNote
                            color: rowFace.ink(Theme.dim)
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                            text: "↵ " + I18n.tr(row.copies ? "launcher.copy"
                                : (row.isCommand ? "launcher.run" : (row.isWeb ? "launcher.search" : "launcher.open")))
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        active: row.kind === "clip"
                        sourceComponent: Component {
                            ClipRow {
                                entry: row.modelData
                                selected: row.selected
                                thumb: row.modelData.thumb || lp.thumbs[row.modelData.id] || ""
                                onWantThumb: lp.requestThumb(row.modelData.id)
                            }
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        active: row.kind === "key" || row.kind === "keygroup"
                        sourceComponent: Component {
                            KeyRow { entry: row.modelData; selected: row.selected }
                        }
                    }
                    // The "clear history" row: once to ask, Enter again to clear (pins stay; DMS's confirm, inline).
                    Item {
                        anchors.fill: parent
                        visible: row.kind === "clipclear"
                        readonly property bool asking: lp.confirmClear && row.selected
                        Icon {
                            id: clearIcon
                            x: 10 + (30 - width) / 2
                            anchors { verticalCenter: parent.verticalCenter; verticalCenterOffset: -Theme.shadowDy / 2 }
                            name: "delete_sweep"
                            glyph: "×"
                            color: parent.asking ? Theme.error : Theme.dim
                        }
                        Text {
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            antialiasing: !Theme.pixelType
                            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                            anchors { left: parent.left; leftMargin: 40 + Theme.gap + 2; right: parent.right; rightMargin: 12
                                      verticalCenter: clearIcon.verticalCenter }
                            elide: Text.ElideRight
                            color: parent.asking ? Theme.error : (row.selected ? Theme.fgOnSelected : Theme.dim)
                            font.pixelSize: Theme.fs
                            font.weight: parent.asking || row.selected ? Theme.wBold : Theme.wMedium
                            font.family: Theme.fam(text, Theme.families)
                            text: (parent.asking ? I18n.tr("launcher.clip.clear_confirm")
                                : I18n.tr((row.modelData.pins || 0) > 0 ? "launcher.clip.clear_pins" : "launcher.clip.clear"))
                                .replace("{n}", row.modelData.count || 0).replace("{p}", row.modelData.pins || 0)
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: row.kind !== "keygroup"
                        onClicked: { lp.sel = row.index; lp.launch() }
                    }
                }
                onCurrentIndexChanged: {
                    // A group's first row also shows its header.
                    if (currentIndex > 0 && lp.results[currentIndex - 1] && lp.results[currentIndex - 1].kind === "keygroup")
                        positionViewAtIndex(currentIndex - 1, ListView.Contain)
                    positionViewAtIndex(currentIndex, ListView.Contain)
                }
            }

            // The start menu's apps (W53.3, `start.grid`): a heading, the grid of icons with their names, then the
            // recommended rows. The selected item (the arrows) and the hovered one stand on the look's menu band.
            Loader {
                active: lp.startGrid
                x: list.x
                y: list.y
                width: list.width
                height: lp.listH
                sourceComponent: Item {
                    id: sv
                    function ink(on) { return on ? ms.ink(Theme.fg) : Theme.fg }
                    component Heading: Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        height: lp.headH
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 24
                        color: Theme.fg
                        font.pixelSize: Theme.fs + 1
                        font.weight: 600
                        font.family: Theme.fam(text, Theme.families)
                    }
                    component AppPic: Item {
                        id: ap
                        property var app: ({})
                        width: 32
                        height: 32
                        readonly property string src: ap.app.icon_path ? "file://" + ap.app.icon_path
                            : (ap.app.icon ? Quickshell.iconPath(ap.app.icon, true) : "")
                        Image {
                            id: pic
                            anchors.fill: parent
                            source: ap.src
                            sourceSize: Qt.size(64, 64)
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: !pic.visible
                            radius: Theme.rSm
                            color: Theme.containerHigh
                            Text {
                                anchors.centerIn: parent
                                color: Theme.dim
                                font.pixelSize: Theme.fs
                                font.weight: Theme.wBold
                                font.family: Theme.fam(text, Theme.families)
                                text: String(ap.app.name || "?").charAt(0).toUpperCase()
                            }
                        }
                    }
                    component Plate: Rectangle {
                        property bool on: false
                        radius: ms.radius(Theme.rSm)
                        color: on ? ms.fill(Theme.containerHigh) : "transparent"
                    }
                    Heading { id: h1; text: I18n.tr(lp.hasPins ? "launcher.start.pinned" : "launcher.start.apps") }
                    Grid {
                        id: cells
                        y: h1.height
                        x: 8
                        columns: lp.startCols
                        Repeater {
                            model: lp.startTop
                            Item {
                                id: cell
                                required property var modelData
                                required property int index
                                width: (sv.width - 16) / lp.startCols
                                height: lp.startCellH
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.name || ""
                                Plate { anchors.fill: parent; anchors.margins: 2; on: cell.index === lp.sel || cellHit.containsMouse }
                                AppPic { app: cell.modelData; anchors.horizontalCenter: parent.horizontalCenter; y: 14 }
                                Text {
                                    anchors { left: parent.left; right: parent.right; margins: 4; top: parent.top; topMargin: 54 }
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    color: sv.ink(cell.index === lp.sel)
                                    font.pixelSize: Theme.fsLabel
                                    font.family: Theme.fam(text, Theme.families)
                                    text: cell.modelData.name || ""
                                }
                                MouseArea {
                                    id: cellHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { lp.sel = cell.index; lp.launch() }
                                }
                            }
                        }
                    }
                    Heading {
                        id: h2
                        visible: lp.startRec.length > 0
                        y: cells.y + cells.height + Theme.gap * 2
                        text: I18n.tr("launcher.start.recommended")
                    }
                    Grid {
                        visible: h2.visible
                        y: h2.y + h2.height
                        x: 8
                        columns: 2
                        Repeater {
                            model: lp.startRec
                            Item {
                                id: rec
                                required property var modelData
                                required property int index
                                readonly property int at: lp.startTop.length + index
                                width: (sv.width - 16) / 2
                                height: lp.recRowH
                                Accessible.role: Accessible.Button
                                Accessible.name: modelData.name || ""
                                Plate { anchors.fill: parent; anchors.margins: 2; on: rec.at === lp.sel || recHit.containsMouse }
                                AppPic { id: rp; app: rec.modelData; x: 16; anchors.verticalCenter: parent.verticalCenter }
                                Column {
                                    anchors { left: rp.right; leftMargin: 12; right: parent.right; rightMargin: 8
                                              verticalCenter: parent.verticalCenter }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        color: sv.ink(rec.at === lp.sel)
                                        font.pixelSize: Theme.fsLabel
                                        font.family: Theme.fam(text, Theme.families)
                                        text: rec.modelData.name || ""
                                    }
                                    Text {
                                        width: parent.width
                                        visible: text !== ""
                                        elide: Text.ElideRight
                                        color: Theme.dim
                                        font.pixelSize: Theme.fsCaption
                                        font.family: Theme.fam(text, Theme.families)
                                        text: rec.modelData.generic || ""
                                    }
                                }
                                MouseArea {
                                    id: recHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { lp.sel = rec.at; lp.launch() }
                                }
                            }
                        }
                    }
                }
            }

            // The emoji grid (`:`): 8 a row, the selected cell a tonal block; its name under the grid.
            GridView {
                id: grid
                visible: lp.mode === "emoji"
                x: list.x
                y: list.y
                width: list.width
                height: lp.listH
                clip: true
                interactive: false
                cacheBuffer: 0
                cellWidth: width / lp.cols
                cellHeight: lp.cellH
                model: lp.mode === "emoji" ? lp.results : []
                currentIndex: lp.sel
                highlightMoveDuration: 0
                highlightFollowsCurrentItem: true
                highlight: Block {
                    width: grid.cellWidth
                    height: grid.cellHeight
                    radius: Theme.rLg
                    ringScale: 0
                    softScale: 0
                    fill: Theme.selected
                    penSeed: 0x1A0F
                }
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -Theme.shadowDy / 2
                        font.pixelSize: 30
                        text: cell.modelData.glyph || ""
                        Accessible.name: cell.modelData.name || ""
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { lp.sel = cell.index; lp.launch() }
                    }
                }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
            }

            // Under the list: the mode's keys (clipboard, cheat sheet), or the selected emoji's name.
            Item {
                visible: lp.footer
                x: card.l0
                y: list.y + lp.listH + Theme.gap
                width: card.w0
                height: 18
                readonly property var cur: lp.results[lp.sel] || null
                Text {
                    id: footLeft
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    width: parent.width - footRight.implicitWidth - 24
                    visible: lp.mode === "emoji"
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.pixelSize: Theme.fsCaption
                    font.weight: Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                    text: parent.cur && parent.cur.kind === "emoji"
                        ? parent.cur.name + (parent.cur.recent ? "  ·  " + I18n.tr("launcher.emoji.recent") : "") : ""
                }
                Text {
                    id: footRight
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(lp.mode === "emoji" ? "launcher.hint.emoji"
                        : (lp.mode === "clip" ? "launcher.hint.clip" : (lp.mode === "keys" ? "launcher.hint.keys" : "")))
                }
            }

            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                anchors { centerIn: lp.mode === "emoji" ? grid : list }
                // Nothing found for what was typed; an empty field is no question, and says nothing (lead review, W53.4).
                visible: lp.results.length === 0 && field.text !== "" && !lp.sysMenu
                color: Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("launcher.empty")
            }

            // W53.4: the system menu's rows (`start.form = menu`), where the list stands: the look's menu row under the
            // chosen one (its band, `ms.rowBackground`, else the selection colour), its ink on it; rules between groups; a
            // group's name dimmed. The pointer chooses too. A row that asks again shows the session menu's words.
            Column {
                visible: lp.sysMenu
                x: card.l0 - Theme.pad
                y: card.inset + 4 + lp.skinHeader
                width: card.w0 + 2 * Theme.pad
                Repeater {
                    model: lp.sysMenu ? lp.sysRows : []
                    delegate: Item {
                        id: srow
                        required property var modelData
                        required property int index
                        readonly property bool on: index === lp.sysSel && lp.sysPick(index)
                        width: parent.width
                        height: lp.sysRowHeight(modelData)
                        Accessible.role: modelData.sep ? Accessible.Separator : Accessible.MenuItem
                        Accessible.name: modelData.label || modelData.head || ""
                        Loader {
                            anchors.fill: parent
                            active: ms.has && !srow.modelData.head
                            source: active ? ms.rowBackground : ""
                            onLoaded: {
                                item.highlighted = Qt.binding(function () { return srow.on })
                                item.separator = Qt.binding(function () { return srow.modelData.sep === true })
                            }
                        }
                        Rectangle {
                            visible: !ms.has && srow.on
                            anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                            radius: ms.radius(Theme.rSm)
                            color: ms.fill(Theme.selected)
                        }
                        Rectangle {
                            visible: !ms.has && srow.modelData.sep === true
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 1 }
                            height: 1
                            color: Theme.color("color.outline_variant", "#c4c4c4")
                        }
                        Text {
                            visible: !srow.modelData.sep
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                      leftMargin: srow.modelData.app ? Theme.pad + 14 : Theme.pad; rightMargin: Theme.pad }
                            elide: Text.ElideRight
                            text: lp.armed === srow.index && srow.modelData.confirm ? I18n.tr(srow.modelData.confirm)
                                : (srow.modelData.label || srow.modelData.head || "")
                            color: srow.on ? ms.ink(Theme.fgOnSelected) : (srow.modelData.head ? Theme.dim : Theme.fg)
                            font.pixelSize: srow.modelData.head ? Theme.fsCaption : Theme.fs
                            font.weight: lp.armed === srow.index ? Theme.wBold : Theme.wRegular
                            font.family: Theme.fam(text, Theme.families)
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: lp.sysPick(srow.index)
                            hoverEnabled: true
                            onEntered: if (lp.sysSel !== srow.index) { lp.sysSel = srow.index; lp.armed = -1 }
                            onClicked: lp.sysRun(srow.index)
                        }
                    }
                }
            }

            // The start menu's footer (row 563): the session's keys under the rows — lock at once, the rest through the
            // session menu and its confirm (a start menu's "Shut down…" opens the shutdown dialog). The launcher closes
            // first: the lock and the menu take the keyboard.
            Row {
                visible: lp.skin && !lp.sysMenu
                anchors { right: parent.right; rightMargin: Theme.pad + card.inset; bottom: parent.bottom
                          bottomMargin: (morph.morph ? 0 : Theme.shadowDy) + Theme.pad + card.inset
                              + (lp.skinFooter - Theme.controlH) / 2 }
                spacing: Theme.gap
                Repeater {
                    model: lp.skin ? [["action.session.lock", "lock", "session.lock"],
                                      ["action.session.menu", "power_settings_new", "session.menu"]] : []
                    delegate: Button {
                        required property var modelData
                        label: I18n.tr(modelData[0])
                        icon: modelData[1]
                        onClicked: { var a = modelData[2]; Store.act("ui.close", {}, function () { Store.act(a) }) }
                    }
                }
            }
        }
    }
}
