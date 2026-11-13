import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components/bar/framegeom.js" as FG
import "../core"
import "../components"
import "../components/launcher"
import "../components/island"
import "../components/sidebar"
import "../components/decor"
import "../components/appearance"
import "../components/appearance/appearance.js" as Appear

// Launcher (M5): centred overlay with exclusive keyboard focus while open. The daemon owns the
// open state (runtime.ui.launcher), the index, ranking and launching; this only renders results
// of `query launcher` and sends `launcher.launch` / `ui.close`.
//
// Prefix modes (K44, I126, W26; docs/ux/launcher.md): `:` emoji as a grid (8 a row, arrows move in two dimensions,
// recent first), `;` the clipboard history (image thumbnails, pins, Shift+Delete removes, a "clear history" row with a
// confirm), `>` commands, `?` the keybind cheat sheet (also action `launcher.keys`: `runtime.ui.launcher_query`).
//
// Same idle discipline as Stage (K16): permanently mapped but transparent, input-less and
// focus-less while hidden, so it renders 0 frames. W67 (I424): typing re-sorts the rows as Caelestia's do — a row that
// stays slides to its new place, a new one comes in, a dropped one leaves (a keyed model, `show()`; cut under reduce motion).
//
// W34 (docs/ux/motion.md): under a top or bottom bar the launcher grows out of the island pill as one shape (BarMorph:
// the island's MorphShape, two springs, the liquid neck at the bar's edge, the pill's face in its head) and folds back
// into it; the card then hangs under the bar's centre and the window covers the bar's strip above it (margin 0, the
// shape's box; K16: its size only, never the output's). Without one (a side bar, no bar) it stays centred on the output
// and slides in, as before. I407: that is one of its places (`launcher.place`), see `place` below.
PanelWindow {
    // (the change of colour as a cross-fade: components/ColorFade.qml)
    ColorFade {}
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
    readonly property int listH: menuOn ? menuH : sysMenu ? sysH : startGrid ? startH : mode === "emoji"
        ? Math.max(1, Math.min(Math.ceil(results.length / cols), gridRows)) * cellH
        : Math.max(rowH, Math.min(contentH, maxListH))
    readonly property bool footer: mode !== "apps" && !menuOn
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
    // Session 33 (the user: "the clipboard section cleaner — text in the list, the image's preview right beside it, as
    // Noctalia v5 does"): the clipboard mode is two columns — one-line rows on the left, the selected entry on the right
    // (its picture large, or its whole text). The start-menu skin keeps its one column.
    readonly property bool clipSplit: mode === "clip" && !skin
    readonly property int clipListW: 340
    // The whole text of the selected entry (the list has its first line), asked for once per entry while shown.
    property var clipTexts: ({})
    property var clipAsked: ({})
    function requestText(id) {
        if (!want || clipAsked[id]) return
        clipAsked[id] = true
        Store.act("launcher.clip.text", { id: id }, function (done, e) {
            if (!lp.want) return
            var t = Object.assign({}, lp.clipTexts)
            t[id] = done && done.data && done.data.text !== undefined ? done.data.text : null
            lp.clipTexts = t
        })
    }
    // ---- W84 (docs/ux/appearance-menu.md): the appearance menu as the launcher's card. Words find it (`appearance:<pane>`
    // rows); Enter shows it on that pane in place of the rows (the field stays, holding the query), Esc goes back to the
    // search. A state beside the prefix modes, not one of them. `launcher.appearance_opens = card` opens it as a Stage card
    // instead (`appearance.open`, CONTRACT-CHANGE row 791); a daemon that lacks the action leaves it here, with a note.
    property string menuPane: ""
    readonly property bool menuOn: menuPane !== ""
    property string menuNote: ""
    readonly property int menuH: 540
    readonly property int menuW: 760
    function openMenu(pane) {
        if (String(bars.valueOf("launcher.appearance_opens", "launcher")) === "card") {
            Store.act("appearance.open", { pane: pane, output: scr ? scr.name : "" }, function (done, e) {
                if (!e || !lp.want) return
                lp.menuNote = I18n.tr("appearance-menu.card_unavailable")
                lp.menuPane = pane
            })
            return
        }
        menuNote = ""
        menuPane = pane
        if (placeLog) console.log("launcher-menu " + pane)
    }
    function closeMenu() {
        menuPane = ""
        menuNote = ""
        field.forceActiveFocus()
    }
    // The dress, made only while the menu is open, for its skin's url (it is not shown here).
    StartHost { id: dressOf; visible: false; active: has && lp.skin && lp.want }
    readonly property url skinUrl: dressOf.ready ? dressOf.item.menu : ""
    property var startAt: null
    property var openedFrom: null
    // I407 (`launcher.place`, docs/ux/launcher.md "Where it opens"), latched on open: `at` hangs it from what was clicked
    // (`startAt`), `island` grows it out of the pill, `centre` and `fixed` stand it on the output. `opened` asks for `at` on
    // a click and `centre` on a key; only a click says where it came from (IslandGeom.noteOpener).
    readonly property string placeCfg: String(bars.valueOf("launcher.place", "opened"))
    property string place: "centre"
    function placeFor(rect) {
        if (placeCfg === "opened") return rect ? "at" : "centre"
        if (placeCfg === "island") return bars.atTop || bars.atBottom ? "island" : "centre"
        return placeCfg === "fixed" ? "fixed" : "centre"
    }
    readonly property string atEdge: place === "at" && startAt ? String(startAt.edge || "top") : ""
    readonly property string skinEdge: atEdge === "bottom" || (place === "island" && bars.atBottom) ? "bottom" : "top"
    readonly property real scrW: scr ? scr.width : 1920
    readonly property real scrH: scr ? scr.height : 1080
    // The card at its tallest: one that stands on the output keeps its top while the rows come and go.
    readonly property real tallH: card.height - listH + Math.max(listH, maxListH) + 2 * morph.shade
    readonly property real fixedX: Number(bars.valueOf("launcher.place_x", 50)) / 100
    readonly property real fixedY: Number(bars.valueOf("launcher.place_y", 50)) / 100
    // I428, dynamic: a launcher opened at a button on a bar stands on that bar, joined to it as the dock is, and merges with what
    // stands beside it when it opens near a corner, with no room for a fillet there (Caelestia's popouts). Not a look's own start menu.
    readonly property var outLay: ShellLayout.of(scr ? scr.name : "")
    function holeSide(e) { return FG.holeSide(outLay, e, Theme.barH) }
    readonly property bool joinsAt: place === "at" && !!startAt && !skin && Theme.surfaceJoin
        && FG.edgeOf(outLay, atEdge).bar === true && FG.edgeOf(outLay, atEdge).draw === "dynamic"
    readonly property bool sideways: atEdge === "left" || atEdge === "right"
    readonly property real mergeRoom: 2 * Theme.rJoin + Theme.pad
    // Where the card would stand along the bar, against what stands at each end.
    readonly property real wantAlong: !startAt ? 0 : sideways ? startAt.y : startAt.x + (startAt.w - card.width) / 2
    readonly property bool mergesStart: joinsAt && wantAlong < holeSide(sideways ? "top" : "left") + mergeRoom
    readonly property bool mergesEnd: joinsAt && !mergesStart && wantAlong + (sideways ? card.height : card.width)
        > (sideways ? scrH - holeSide("bottom") : scrW - holeSide("right")) - mergeRoom
    // The window's top and left on the output, for `at` beside a side bar and for the places on the output.
    readonly property real standX: {
        // (the card's place: the window round it may stand past the screen's edge, with its shadow's room)
        var room = Math.max(0, scrW - implicitWidth)
        if (place === "fixed") return Math.round(Math.max(0, scrW - implicitWidth + 2 * morph.shade) * fixedX) - morph.shade
        if (place !== "at" || !startAt) return Math.round(room / 2)
        if (joinsAt) {
            if (atEdge === "left") return holeSide("left") - morph.shade
            if (atEdge === "right") return scrW - holeSide("right") - card.width - morph.shade
            if (mergesStart) return holeSide("left") - morph.shade
            if (mergesEnd) return scrW - holeSide("right") - card.width - morph.shade
        }
        if (atEdge === "left") return Math.round(startAt.x + startAt.w + hangGap - morph.shade)
        if (atEdge === "right") return Math.round(startAt.x - hangGap - implicitWidth + morph.shade)
        if (Theme.decor("start.menu", "button") === "center") return Math.round(room / 2)
        // A start menu's corner stands at its button; another card is centred under what opened it.
        var x = skin ? startAt.x - morph.shade : startAt.x + (startAt.w - implicitWidth) / 2
        return Math.round(Math.max(holeSide("left") + Theme.gap - morph.shade,
            Math.min(room - holeSide("right") - Theme.gap + morph.shade, x)))
    }
    readonly property real standY: {
        var room = Math.max(0, scrH - tallH)
        if (place === "fixed") return Math.round(Math.max(0, scrH - tallH + 2 * morph.shade) * fixedY) - morph.shade
        if (place === "island") return (bars.atBottom ? 0 : bars.topInset) - morph.shade
        if (place !== "at" || !startAt) return Math.round(room / 2)
        if (joinsAt) {
            if (atEdge === "top") return holeSide("top") - morph.shade
            if (mergesStart) return holeSide("top") - morph.shade
            if (mergesEnd) return scrH - holeSide("bottom") - card.height - morph.shade
        }
        if (atEdge === "left" || atEdge === "right") return Math.round(Math.max(-morph.shade, Math.min(room + morph.shade, startAt.y - morph.shade)))
        return startAt.y + startAt.h + hangGap - morph.shade
    }
    // Under a bar with the shape out the compositor centres the window on the bar; every other place sets the corner.
    readonly property bool hangsOnBar: place === "island" && morph.layout
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
    readonly property bool startGrid: startCols > 0 && mode === "apps" && field.text === "" && field.preeditText === "" && !menuOn
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
    readonly property bool sysMenu: skin && Theme.decor("start.form", "search") === "menu" && mode === "apps" && !menuOn
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
    onSysMenuChanged: { sysSel = 0; armed = -1; listSel = false }
    // The look's menu rows (row 591): its highlight's shape and corner, its part under each row.
    MenuStyle { id: ms }

    function heightOf(r) {
        switch (r.kind) {
        case "keygroup": return 30
        case "key": return 38
        case "clip": return lp.clipSplit ? 46 : (r.image ? 72 : 58)
        default: return rowH
        }
    }
    // Test only (KURASHI_LAUNCHER_LOG=1): where it stands once open. Without the variable: no timer, no log.
    readonly property bool placeLog: Quickshell.env("KURASHI_LAUNCHER_LOG") === "1"
    Timer {
        id: placeLogTimer
        interval: 500
        onTriggered: console.log("launcher-place " + lp.place + " " + lp.scrW + " " + lp.scrH + " " + lp.margins.left + " " + lp.margins.top
            + " " + lp.implicitWidth + " " + lp.implicitHeight + " " + lp.footAnchored + " " + morph.shade)
    }
    function screenNamed(name) {
        var s = Quickshell.screens
        for (var i = 0; i < s.length; i++) if (s[i].name === name) return s[i]
        return null
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
        picked = true
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
            // A reply to a query already typed past is dropped: a fast typist's last list is the one that stays.
            if (q !== field.text) return
            var old = lp.sel
            var oldKey = lp.picked && lp.listSel && old >= 0 && old < lp.shownKeys.length ? lp.shownKeys[old] : ""
            lp.applying = true
            // (no current row while the diff applies: a view whose current row moves follows it, and laid out the list
            // around that row's passing place — rows that stayed were scrolled out and made again)
            list.currentIndex = -1
            grid.currentIndex = -1
            // W84 stand-in (CONTRACT-CHANGE row 790): the appearance menu's rows first, until the daemon offers them.
            lp.show(Appear.mergeRows(q, items || [], I18n.tr))
            // A row the user chose (the arrows) stays chosen by key while it stays in the list, wherever it moves; else
            // today's rule: the first selectable row — the best hit, which Enter opens — or the same place after a
            // clipboard action.
            var at = oldKey !== "" ? lp.shownKeys.indexOf(oldKey) : -1
            if (!lp.selectable(at)) lp.picked = false
            lp.sel = lp.selectable(at) ? at : lp.settle(keep ? Math.min(old, lp.results.length - 1) : 0, 1)
            lp.listSel = true
            lp.syncCurrent()
            lp.applying = false
            if (lp.mode === "emoji") grid.reveal()
            else list.reveal()
            lp.err = e ? lp.errorText(e) : ""
            if (lp.placeLog) console.log("launcher-rows " + JSON.stringify({ q: q, sel: lp.shownKeys[lp.sel] || "", keys: lp.shownKeys, motion: lp.listMotion }))
        })
    }

    // ---- W67 (I424, docs/ux/launcher.md "Results while typing"): the rows are a keyed model. Each reply is diffed against
    // the rows shown by a stable key, and only the moves, inserts and removes are applied, so a row that stays keeps its
    // delegate and slides to its new place (Caelestia's AppList, there through ScriptModel; here the daemon sends fresh
    // objects each time, so the key is ours). `results` stays the plain list every other binding reads.
    ListModel { id: rowModel }
    // key → row of the latest reply (a delegate reads its data here and latches it, so a leaving row keeps its face).
    property var byKey: ({})
    property var shownKeys: []
    // Whether `sel` names a row of this list (the start menu's grid and system menu count their own items).
    property bool listSel: false
    // Whether the user moved the selection (arrows, Page keys) since the open or since the chosen row left the list.
    property bool picked: false
    onStartGridChanged: listSel = false
    property int made: 0         // delegates made (the test's creation counter, KURASHI_LAUNCHER_LOG=1)
    // Transitions run only between two replies of one open and one mode: the first fill of an open (under the morph's
    // late content) or of a new prefix mode is a new list, not a re-sort; hidden, nothing animates (Ma); reduce motion
    // and `none` (`motion.spring.on` false) cut.
    property bool primed: false
    property bool live: false
    readonly property bool listMotion: live && shown && want && Theme.springOn
    function unprime() { live = false; primed = false }
    // A row's identity: the daemon's id (desktop id, `cmd:`, `clip:`, `emoji:` …), else its kind and text (a cheat sheet
    // row, a group, a note carry no id). A calculation and the web row are one row each whatever they say (their ids
    // carry the value or the query); repeats in one list get a count.
    function keyOf(r) {
        var kind = String(r.kind || "")
        if (kind === "calc" || kind === "web") return kind
        if (r.id) return kind + ":" + r.id
        return kind + ":" + (r.name || "") + "\u001f" + (r.generic || "") + "\u001f" + (r.group || "")
    }
    function show(items) {
        if (primed) live = true
        var keys = [], map = ({}), seen = ({})
        for (var i = 0; i < items.length; i++) {
            var k = keyOf(items[i])
            var n = seen[k] || 0
            seen[k] = n + 1
            if (n > 0) k += "#" + n
            keys.push(k)
            map[k] = items[i]
        }
        byKey = map
        var cur = shownKeys.slice()
        // Leaving rows first (from the end), then each place in turn: the row that belongs there moves up, or comes in.
        for (i = cur.length - 1; i >= 0; i--)
            if (map[cur[i]] === undefined) { rowModel.remove(i, 1); cur.splice(i, 1) }
        for (i = 0; i < keys.length; i++) {
            if (cur[i] === keys[i]) continue
            var j = cur.indexOf(keys[i], i + 1)
            if (j >= 0) { rowModel.move(j, i, 1); cur.splice(j, 1) }
            else rowModel.insert(i, { k: keys[i] })
            cur.splice(i, 0, keys[i])
        }
        shownKeys = cur
        results = items
        primed = true
    }
    function clearRows() {
        unprime()
        listSel = false
        picked = false
        // (the list first, then its rows: with the rows emptied first, the scroll host once reported a binding loop on
        // `overflows` — seen with this order changed among other fixes, so the order is a guess at the cause)
        results = []
        rowModel.clear()
        shownKeys = []
        byKey = ({})
    }
    // The views' current row follows `sel` by hand: a move or remove inside the model shifts a view's currentIndex on
    // its own, and a bound `currentIndex: sel` would not re-fire when `sel` keeps its value.
    function syncCurrent() {
        if (list.currentIndex !== sel) list.currentIndex = sel
        if (grid.currentIndex !== sel) grid.currentIndex = sel
    }
    property bool applying: false
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
        if (id.indexOf("appearance:") === 0) { openMenu(id.substring("appearance:".length)); return }
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
    onSelChanged: { confirmClear = false; syncCurrent() }
    onModeChanged: { confirmClear = false; unprime() }

    screen: scr
    BarConfig { id: bars; screen: lp.scr }
    // While the shape is out under a top or bottom bar, one vertical edge anchored (the compositor centres the surface
    // horizontally, so the shape's box is centred on the bar). Every other place: its corner on the output (I407), the
    // window's shade round the card counted; under a bottom bar it is the foot that stays.
    readonly property bool footAnchored: atEdge === "bottom" || (place === "island" && bars.atBottom)
    anchors {
        top: !footAnchored
        bottom: footAnchored
        left: !hangsOnBar
    }
    // (W53.4: a start menu that hangs from its bar, `[decor] flyout.hang` — Mac OS X's menus — meets it, no gap)
    readonly property int hangGap: Theme.decor("flyout.hang", false) === true ? 0 : Theme.gap
    // I435: a translucent card that stands on the bar has the rule left out under it and the sheet's shadow cut.
    CardJoin {
        output: lp.scr ? lp.scr.name : ""
        side: "launcher"
        on: lp.joinsAt && lp.want && !morph.morph && Theme.tok("color.surface_alpha", 1) < 0.999
        readonly property real cx: lp.standX + morph.shade
        readonly property real cy: lp.footAnchored ? lp.scrH - lp.margins.bottom - morph.shade - card.height : lp.standY + morph.shade
        spans: {
            var j = Theme.rJoin, w = card.width, h = card.height, l = []
            if (lp.sideways) {
                l.push({ edge: lp.atEdge, from: cy - (lp.mergesStart ? 0 : j), to: cy + h + (lp.mergesEnd ? 0 : j) })
                if (lp.mergesStart) l.push({ edge: "top", from: cx, to: cx + w + j })
                if (lp.mergesEnd) l.push({ edge: "bottom", from: cx, to: cx + w + j })
            } else {
                l.push({ edge: lp.atEdge, from: cx - (lp.mergesStart ? 0 : j), to: cx + w + (lp.mergesEnd ? 0 : j) })
                if (lp.mergesStart) l.push({ edge: "left", from: cy, to: cy + h + j })
                if (lp.mergesEnd) l.push({ edge: "right", from: cy, to: cy + h + j })
            }
            return l
        }
        box: Qt.rect(cx, cy, card.width, card.height)
    }
    margins.left: hangsOnBar ? 0 : standX
    margins.top: hangsOnBar || footAnchored ? 0 : standY
    margins.bottom: hangsOnBar || !footAnchored ? 0
        : joinsAt ? holeSide("bottom") - morph.shade
        : (startAt ? scrH - startAt.y + hangGap : bars.bottomInset) - morph.shade
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
            // (a click names its output and its place; a key opens on the focused output)
            var by = IslandGeom.takeOpener()
            scr = by ? (screenNamed(by.output) || focusedScreen()) : focusedScreen()
            place = placeFor(by ? by.rect : null)
            startAt = place === "at" ? by.rect : null
            openedFrom = startAt
            if (placeLog) placeLogTimer.restart()
            clearRows(); sel = 0; err = ""; confirmClear = false
            menuPane = ""; menuNote = ""
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
        surface: "launcher"
        outName: lp.scr ? lp.scr.name : ""
        // (room for the fillets round a card that stands on its bar; its corners there are the bar's)
        // (and for the card's elevation, level 4 below: with less, the window cuts it square and only the corners show it)
        shade: Math.max(lp.joinsAt ? Math.max(Theme.softR, Theme.rJoin + 2) : Theme.softR, morph.morph ? 0 : Theme.elevReach(4))
        cardRNear: morph.morph || lp.joinsAt ? 0 : Theme.rLg
        onBar: lp.place === "island"
        flip: lp.skinEdge !== "top"
        open: lp.want
        cardW: card.width
        cardH: card.height
        slide: 12
        slideScale: 0.96
        // S21: a start menu's sheet form pours out of its start button (the window's frame: its margins off the screen).
        formOrigin: lp.place === "at" && lp.openedFrom && lp.scr ? Qt.rect(lp.openedFrom.x - lp.margins.left,
            !lp.footAnchored ? lp.openedFrom.y - lp.margins.top
                : lp.openedFrom.y - (lp.scr.height - lp.margins.bottom - lp.implicitHeight),
            lp.openedFrom.w, lp.openedFrom.h) : Qt.rect(0, 0, 0, 0)
        onHidden: { lp.clearRows(); lp.thumbs = ({}); lp.clipTexts = ({}); lp.clipAsked = ({}); lp.menuPane = "" }

        // The card's content. In the morph the shape is its chrome; sliding in, it is a Block (K42, K45): a flat panel with a
        // hairline, a keycap panel with an ink outline and hard shadow, a soft glass panel with a rim and a drop shadow, or a
        // panel outlined in ink (line).
        Item {
            id: card
            width: lp.menuOn ? lp.menuW + lp.skinBand : lp.skin ? lp.skinW + lp.skinBand : (lp.clipSplit ? 880 : 600)
            // I503: all text written in on opening, under `theme.typography.fx.scope = all` (components/TextSpawnAll.qml).
            TextSpawnAll { root: card; shown: lp.shown }
            // I458: a launcher a hover opened stays while the pointer is on it, and is the user's once they press in it.
            HoverHandler { onHoveredChanged: hovered ? Peeks.hoverHold() : Peeks.hoverLeave() }
            PointHandler { acceptedButtons: Qt.AllButtons; onActiveChanged: if (active) Peeks.hoverKeep() }
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
                radius: Theme.rLg
                level: 4
                cutTop: lp.joinsAt && (lp.atEdge === "top" || (lp.sideways && lp.mergesStart))
                cutBottom: lp.joinsAt && (lp.atEdge === "bottom" || (lp.sideways && lp.mergesEnd))
                cutLeft: lp.joinsAt && (lp.atEdge === "left" || (!lp.sideways && lp.mergesStart))
                cutRight: lp.joinsAt && (lp.atEdge === "right" || (!lp.sideways && lp.mergesEnd))
            }
            // I428: standing on its bar, one sheet with it; else the block.
            JoinedCard {
                visible: lp.joinsAt && !morph.morph
                x: -morph.shade
                y: -morph.shade
                width: card.width + 2 * morph.shade
                height: card.height + 2 * morph.shade
                pad: morph.shade
                edge: lp.atEdge
                flushStart: lp.mergesStart
                flushEnd: lp.mergesEnd
            }
            Block {
                visible: !morph.morph && !skinPart.ready && !lp.joinsAt
                anchors.fill: parent
                radius: Theme.rLg
                fill: Theme.panel
                // (W75, B118: the still ink while hidden — the closed launcher's window stays mapped)
                flatBorder: visible ? Theme.surfaceHair : (Theme.frameOutline ? Theme.frameOutlineStill : "transparent")
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
                // W53.8 (`filled`): M3's search bar — the container-high tone, no outline, no well.
                readonly property bool filled: Theme.decor("field.form", "box") === "filled"
                framed: !underline && !filled
                // A text field is a well (row 591): sunken under a bevel chrome, nothing otherwise.
                sunken: !underline && !filled
                fill: underline ? "transparent" : (filled ? Theme.containerHigh : Theme.surface)
                flatBorder: underline || filled ? "transparent" : (field.activeFocus ? Theme.accent : Theme.outline)
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
                    onTextChanged: { if (text !== "") Peeks.hoverKeep(); if (lp.want) lp.run(text) }
                    // W84: back in the field (a click), back to the search.
                    onActiveFocusChanged: if (activeFocus && lp.menuOn) { lp.menuPane = ""; lp.menuNote = "" }
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
                        // (a block caret stands before the words, as a terminal's cursor before its prompt's text)
                        anchors.leftMargin: Theme.decor("field.caret", "bar") === "block" ? Math.round(phFm.averageCharacterWidth) : 0
                        FontMetrics { id: phFm; font: field.font }
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
                x: lp.clipSplit ? list.x + list.width - width : card.l0 + card.w0 - width
                y: list.y
                stepPx: lp.rowH
            }
            // Session 33: the clipboard's preview, beside its list — the selected entry's picture, large, or its whole text,
            // with what it is and the keys under it. Asked for only for the selected entry (Ma).
            Item {
                id: clipPane
                visible: lp.clipSplit && list.visible
                x: list.x + list.width + Theme.pad
                y: list.y
                width: Math.max(0, card.l0 + card.w0 - x)
                height: lp.listH
                readonly property var entry: lp.results[lp.sel] || null
                readonly property bool isClip: !!entry && entry.kind === "clip"
                readonly property bool isImage: isClip && !!entry.image
                readonly property bool isPin: isClip && String(entry.id).indexOf("clip:pin:") === 0
                readonly property string thumb: isImage ? (entry.thumb || lp.thumbs[entry.id] || "") : ""
                readonly property var full: isClip && !isImage && !entry.binary ? lp.clipTexts[entry.id] : undefined
                readonly property string shownText: full !== undefined && full !== null ? full : (isClip ? String(entry.name || "") : "")
                readonly property int lines: shownText === "" ? 0 : shownText.split("\n").length
                function ask() {
                    if (!isClip || !lp.clipSplit) return
                    if (isImage) { if (thumb === "") lp.requestThumb(entry.id) }
                    else if (!entry.binary && !isPin) lp.requestText(entry.id)
                }
                onEntryChanged: Qt.callLater(ask)
                Accessible.role: Accessible.Pane
                Accessible.name: I18n.tr("launcher.clip.preview")

                Rectangle {
                    id: paneGround
                    anchors.fill: parent
                    radius: Theme.nested(Theme.rLg, Theme.pad)
                    color: Theme.container
                    border.width: Theme.outlineW > 0 ? Theme.outlineW : 1
                    border.color: Theme.outlineW > 0 ? Theme.outlineColor : Theme.outline
                }
                // the picture
                Image {
                    id: paneImg
                    visible: clipPane.isImage && status === Image.Ready
                    anchors { fill: parent; margins: Theme.pad; bottomMargin: paneMeta.height + 2 * Theme.pad }
                    source: clipPane.thumb !== "" && clipPane.thumb !== "!" ? "file://" + clipPane.thumb : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    smooth: !Theme.pixelType
                }
                // the text
                Flickable {
                    id: paneFlick
                    visible: clipPane.isClip && !clipPane.isImage
                    anchors { fill: parent; margins: Theme.pad; bottomMargin: paneMeta.height + 2 * Theme.pad }
                    contentHeight: paneText.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    KineticWheel { view: paneFlick }
                    Text {
                        id: paneText
                        width: paneFlick.width
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: clipPane.entry && clipPane.entry.binary ? Theme.dim : Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: clipPane.entry && clipPane.entry.binary ? I18n.tr("launcher.clip.binary") : clipPane.shownText
                    }
                }
                ScrollEdge { view: paneFlick }
                // nothing to show (the "clear history" row, a note): the pane's mark
                Icon {
                    anchors.centerIn: parent
                    visible: !clipPane.isClip || (clipPane.isImage && !paneImg.visible)
                    name: clipPane.isImage ? (clipPane.thumb === "!" ? "hide_image" : "image") : "content_paste"
                    glyph: "⎘"
                    size: 36
                    color: Theme.dim
                    opacity: 0.6
                }
                // what it is, and the keys
                Column {
                    id: paneMeta
                    visible: clipPane.isClip
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.pad }
                    spacing: 2
                    Row {
                        spacing: Theme.gap
                        Icon {
                            visible: !!(clipPane.entry && clipPane.entry.pinned)
                            name: "push_pin"; glyph: "●"; filled: true; size: Theme.fs; color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                            text: !clipPane.isClip ? "" : clipPane.isImage
                                ? String(clipPane.entry.name || "") + (clipPane.entry.generic ? " · " + clipPane.entry.generic : "")
                                : I18n.tr(clipPane.lines === 1 ? "launcher.clip.chars_line" : "launcher.clip.chars")
                                    .replace("{n}", clipPane.shownText.length).replace("{l}", clipPane.lines)
                        }
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("launcher.clip.keys")
                    }
                }
            }
            // W84: the appearance menu in place of the rows, made only while shown (Ma); it takes the keyboard from the field.
            Loader {
                id: menuHost
                active: lp.menuOn && lp.want
                visible: active
                x: card.l0
                y: lp.err !== "" ? errRow.y + errRow.height + Theme.gap : box.y + box.height + Theme.gap
                width: card.w0
                height: lp.listH
                sourceComponent: AppearanceMenu {
                    host: "launcher"
                    pane: lp.menuPane
                    output: lp.scr ? lp.scr.name : ""
                    note: lp.menuNote
                    onBack: lp.closeMenu()
                }
                onLoaded: item.forceActiveFocus()
            }
            // I494: content cut by the view's edge blends out (components/ScrollEdge.qml).
            ScrollEdge { view: list }
            ListView {
                id: list
                KineticWheel { view: list }
                visible: lp.mode !== "emoji" && !lp.startGrid && !lp.sysMenu && !lp.menuOn
                x: card.l0
                y: lp.err !== "" ? errRow.y + errRow.height + Theme.gap : box.y + box.height + (lp.sysMenu ? 0 : Theme.gap)
                width: lp.clipSplit ? lp.clipListW : card.w0 - (listBar.shown ? listBar.width + 4 : 0)
                height: lp.listH
                clip: true
                interactive: false
                // Only the rows on screen exist, so only their thumbnails are asked for (Ma).
                cacheBuffer: 0
                // The keyed rows (W67, `show()`); the current row is set by `syncCurrent()`, not bound (see there).
                model: lp.mode !== "emoji" && !lp.startGrid ? rowModel : null
                Accessible.role: Accessible.List
                Accessible.name: I18n.tr("launcher.results")
                highlightMoveDuration: 0
                // W67 (docs/ux/launcher.md "Results while typing", Caelestia's AppList): a row that stays slides to its new
                // place, a new one fades and grows in, a dropped one fades out. Interrupted, a row continues from where it
                // is (and an interrupted arrival still ends whole: the slides take opacity and scale to 1 too).
                add: Transition {
                    enabled: lp.listMotion
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
                    NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
                }
                remove: Transition {
                    enabled: lp.listMotion
                    NumberAnimation { property: "opacity"; to: 0; duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                    NumberAnimation { property: "scale"; to: 0.94; duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                }
                // A row that comes into view from past an edge does not travel the whole way: several would start stacked at
                // the edge and slide in over each other. It fades in over the last few pixels instead (read once per row,
                // when its transition starts).
                move: Transition { id: slide
                    enabled: lp.listMotion
                    NumberAnimation { property: "y"; from: list.entryY(slide.ViewTransition.item, slide.ViewTransition.destination); duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                    NumberAnimation { property: "opacity"; from: list.entryOpacity(slide.ViewTransition.item); to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                    NumberAnimation { property: "scale"; to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                }
                displaced: slide
                function outside(it) { return !!it && (it.y >= contentY + height - 1 || it.y + it.height <= contentY + 1) }
                function entryY(it, d) {
                    if (!it) return 0
                    return outside(it) ? d.y + (it.y > d.y ? 1 : -1) * Math.min(8, Math.abs(it.y - d.y)) : it.y
                }
                function entryOpacity(it) { return !it ? 1 : (outside(it) ? 0 : it.opacity) }
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
                    // The row's key (`keyOf`) and its data, latched: a row that leaves keeps what it showed while it fades.
                    required property string k
                    required property int index
                    property var entry: ({})
                    readonly property var fresh: lp.byKey[k]
                    onFreshChanged: if (fresh !== undefined) entry = fresh
                    property int serial: 0
                    Component.onCompleted: {
                        entry = lp.byKey[k] || ({})
                        serial = ++lp.made
                        if (lp.placeLog) console.log("launcher-row made " + serial + " " + k)
                    }
                    Component.onDestruction: if (lp.placeLog) console.log("launcher-row gone " + serial + " " + k)
                    // (a11y: the row as a list item; the selection is the item's, and follows it when the list re-sorts)
                    Accessible.role: kind === "keygroup" ? Accessible.Heading : Accessible.ListItem
                    Accessible.name: kind === "web" ? I18n.tr("launcher.web").replace("{q}", entry.name || "")
                        : (kind === "note" ? I18n.tr(entry.name || "").replace("{path}", entry.arg || "") : (entry.name || ""))
                    Accessible.description: entry.generic || ""
                    Accessible.selectable: kind !== "keygroup"
                    Accessible.selected: selected
                    readonly property string kind: entry.kind || ""
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
                    height: lp.heightOf(entry)

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
                            // W53.6: `[decor] menu.icons` dims or hides the icon.
                            x: 10 + ms.lead; anchors.verticalCenter: parent.verticalCenter
                            visible: ms.icons !== "hide"
                            opacity: ms.icons === "dim" ? 0.55 : 1
                            scale: ms.icons === "dim" ? 0.7 : 1
                            anchors.verticalCenterOffset: -Theme.shadowDy / 2
                            width: 30; height: 30
                            // Row 380 (I190): the file the daemon resolved from the icon theme, loaded asynchronously (off the GUI
                            // thread). Only a name it found no file for asks Qt's icon theme (~20 ms on the GUI thread per new name).
                            property string src: row.kind !== "app" ? ""
                                : (row.entry.icon_path ? "file://" + row.entry.icon_path
                                : (row.entry.icon ? Quickshell.iconPath(row.entry.icon, true) : ""))
                            Image {
                                id: img
                                anchors.fill: parent
                                source: ico.src
                                sourceSize: Qt.size(60, 60)
                                asynchronous: true
                                visible: ico.src !== "" && status === Image.Ready
                                // The app icons' tint (`theme.colors.app_icons`, K110).
                                layer.enabled: Theme.iconTint !== "original" && visible
                                layer.effect: IconTint { mode: Theme.iconTint }
                            }
                            // The app's picture: its relief on its own pixels, masked by its alpha (row 285), so a transparent row's
                            // ground does not halo. A fallback tile carries its own relief (below).
                            Loader {
                                active: Theme.texControls && img.visible && !!(Window.window && QsWindow.window && QsWindow.window.tileSheet)
                                anchors.fill: parent
                                sourceComponent: Item {
                                    anchors.fill: parent
                                    StillCopy {
                                        id: pictureMask
                                        width: parent.width
                                        height: parent.height
                                        sourceItem: img
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
                                    visible: row.isCalc || row.isNote || row.isCommand || row.isWeb || row.kind === "appearance"
                                    name: row.isCalc ? "calculate"
                                        : ((row.isCommand || row.isWeb || row.kind === "appearance") ? (row.entry.icon || "bolt") : "info")
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
                                    text: row.entry.glyph || ""
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
                                    text: (row.entry.name || "?").charAt(0).toUpperCase()
                                    TextFx { title: true }
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
                            // W53.6: `menu.align = center` sets the text centred between the row's ends (no hint: that room is
                            // the marks'); the icon keeps its place at the start.
                            readonly property bool centred: ms.align === "center"
                            readonly property real side: (ico.visible ? ico.x + ico.width : 10 + ms.lead) + Theme.gap + 2
                            anchors { left: parent.left; leftMargin: centred ? Math.max(side, 12 + ms.trail) : side; right: centred ? parent.right : hint.left
                                      rightMargin: centred ? Math.max(side, 12 + ms.trail) : 8
                                      verticalCenter: ico.verticalCenter }
                            Text {
                                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                antialiasing: !Theme.pixelType
                                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                                width: parent.width
                                horizontalAlignment: parent.centred ? Text.AlignHCenter : Text.AlignLeft
                                elide: Text.ElideRight
                                wrapMode: row.isNote ? Text.Wrap : Text.NoWrap
                                maximumLineCount: 2
                                color: rowFace.ink(row.selected ? Theme.fgOnSelected : Theme.fg)
                                font.pixelSize: row.isCalc ? Theme.fsTitle + 2 : (row.isNote ? Theme.fs - 1 : Theme.fs)
                                font.weight: row.isCalc || row.selected ? Theme.wBold : Theme.wMedium
                                font.family: Theme.fam(text, Theme.families)
                                text: row.isNote ? I18n.tr(row.entry.name).replace("{path}", row.entry.arg || "")
                                    : (row.isWeb ? I18n.tr("launcher.web").replace("{q}", row.entry.name) : row.entry.name)
                            }
                            Text {
                                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                                antialiasing: !Theme.pixelType
                                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                                width: parent.width
                                horizontalAlignment: parent.centred ? Text.AlignHCenter : Text.AlignLeft
                                visible: !!row.entry.generic
                                elide: Text.ElideRight
                                color: rowFace.ink(Theme.dim)
                                font.pixelSize: Theme.fs - 2
                                font.family: Theme.fam(text, Theme.families)
                                text: row.entry.generic || ""
                            }
                        }
                        // What Enter does on the selected row: launch, or copy a calculation.
                        Text {
                            id: hint
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            antialiasing: !Theme.pixelType
                            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                            anchors { right: parent.right; rightMargin: 12 + ms.trail; verticalCenter: ico.verticalCenter }
                            visible: row.selected && !row.isNote && ms.align !== "center"
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
                                entry: row.entry
                                selected: row.selected
                                compact: lp.clipSplit
                                thumb: row.entry.thumb || lp.thumbs[row.entry.id] || ""
                                onWantThumb: lp.requestThumb(row.entry.id)
                            }
                        }
                    }
                    Loader {
                        anchors.fill: parent
                        active: row.kind === "key" || row.kind === "keygroup"
                        sourceComponent: Component {
                            KeyRow { entry: row.entry; selected: row.selected }
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
                                : I18n.tr((row.entry.pins || 0) > 0 ? "launcher.clip.clear_pins" : "launcher.clip.clear"))
                                .replace("{n}", row.entry.count || 0).replace("{p}", row.entry.pins || 0)
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: row.kind !== "keygroup"
                        onClicked: { lp.sel = row.index; lp.launch() }
                    }
                }
                // (not while a reply is applied: a move inside the model shifts currentIndex on its own, and laying the view
                // out halfway through the diff read sizes for the old list; the reply reveals its row once applied)
                onCurrentIndexChanged: if (!lp.applying) reveal()
                function reveal() {
                    if (currentIndex < 0 || count === 0) return
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
                            // The app icons' tint (`theme.colors.app_icons`, K110).
                            layer.enabled: Theme.iconTint !== "original" && visible
                            layer.effect: IconTint { mode: Theme.iconTint }
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
                                TextFx { title: true }
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
            // I494: content cut by the view's edge blends out (components/ScrollEdge.qml).
            ScrollEdge { view: grid }
            GridView {
                id: grid
                KineticWheel { view: grid }
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
                model: lp.mode === "emoji" ? rowModel : null
                Accessible.role: Accessible.List
                // W67: the cells re-sort as the rows do (x and y); the selected cell carries its own block, so the
                // selection travels with its emoji instead of jumping ahead of it.
                add: Transition {
                    enabled: lp.listMotion
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
                    NumberAnimation { property: "scale"; from: 0.8; to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.enterCurve }
                }
                remove: Transition {
                    enabled: lp.listMotion
                    NumberAnimation { property: "opacity"; to: 0; duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                    NumberAnimation { property: "scale"; to: 0.8; duration: Theme.quickMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                }
                // (a cell that comes in from past the edge fades in at its place, as a list row does)
                move: Transition { id: cellSlide
                    enabled: lp.listMotion
                    NumberAnimation { property: "x"; from: grid.entry(cellSlide.ViewTransition.item, cellSlide.ViewTransition.destination, "x"); duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                    NumberAnimation { property: "y"; from: grid.entry(cellSlide.ViewTransition.item, cellSlide.ViewTransition.destination, "y"); duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                    NumberAnimation { property: "opacity"; from: grid.entry(cellSlide.ViewTransition.item, null, "opacity"); to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                    NumberAnimation { property: "scale"; to: 1; duration: Theme.stdMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.continuousCurve }
                }
                displaced: cellSlide
                function entry(it, d, p) {
                    if (!it) return p === "opacity" ? 1 : 0
                    var out = it.y >= contentY + height - 1 || it.y + it.height <= contentY + 1
                    if (p === "opacity") return out ? 0 : it.opacity
                    return out ? d[p] : it[p]
                }
                delegate: Item {
                    id: cell
                    required property string k
                    required property int index
                    property var entry: ({})
                    readonly property var fresh: lp.byKey[k]
                    onFreshChanged: if (fresh !== undefined) entry = fresh
                    property int serial: 0
                    Component.onCompleted: {
                        entry = lp.byKey[k] || ({})
                        serial = ++lp.made
                        if (lp.placeLog) console.log("launcher-row made " + serial + " " + k)
                    }
                    Component.onDestruction: if (lp.placeLog) console.log("launcher-row gone " + serial + " " + k)
                    readonly property bool selected: index === lp.sel
                    Accessible.role: Accessible.ListItem
                    Accessible.name: entry.name || ""
                    Accessible.selectable: true
                    Accessible.selected: selected
                    width: grid.cellWidth
                    height: grid.cellHeight
                    Block {
                        anchors.fill: parent
                        visible: cell.selected
                        radius: Theme.rLg
                        ringScale: 0
                        softScale: 0
                        fill: Theme.selected
                        penSeed: 0x1A0F
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -Theme.shadowDy / 2
                        font.pixelSize: 30
                        text: cell.entry.glyph || ""
                        Accessible.name: cell.entry.name || ""
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { lp.sel = cell.index; lp.launch() }
                    }
                }
                onCurrentIndexChanged: if (!lp.applying) reveal()
                function reveal() { if (currentIndex >= 0 && count > 0) positionViewAtIndex(currentIndex, GridView.Contain) }
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
