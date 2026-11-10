import QtQuick
import Quickshell
import "../core"
import "expanded"
import "quick"
import "phone"
import "decor"

// The quick settings card (K24, W13; docs/ux/quick-settings.md): the `quick` panel of runtime.ui, opened by the bar's button or
// `quick.toggle`. The tiles are the view: a status sentence, ten core tiles (Wi-Fi, Bluetooth, Focus, Audio, Power, Display,
// keep awake, night light, record, dark mode), the mod tiles of `quick.tiles`, the output and brightness levels, the media
// row while something plays, and the session footer.
// A tile's arrow, a status segment, or Right opens its page in the same card: the content slides, Esc or ← goes back, and Esc
// on the tiles closes the card (through the Stage). Every document the card shows is watched while it is up (Ma); a page
// watches what it lists only while it is on screen. The controls (W70, quick/*Control.qml) are made here, so a tile and its
// page show one request state.
// W70 (d, docs/ux/control-centre-modules.md): the centre is a card as every other — the Stage draws its chrome (the bars'
// join, material and outline) and the centre its rows in the card's padding; its tiles are Blocks (QuickTile).
// W21 (K42, SekaiPop's "the control center is a phone"), now `quick.style = phone`, off by default: the card is a phone
// (PhoneFrame) — a status row with the time and the glyphs of what the card already watches, a greeting row, keycap tiles
// and pill levels; the pages slide inside the screen. The phone, and a look's flyout, are the card's own chrome
// (`ownChrome`): the Stage draws no card background around them (it reads the same setting, Stage.qml `quickOwnChrome`).
Item {
    id: quick
    readonly property bool phoneStyle: {
        var v = ((Store.docs["config"] || {}).values || {})["quick.style"]
        return !!v && v.value === "phone"
    }
    readonly property bool ownChrome: phoneStyle || flyout
    // The plain card: no frame of the centre's own.
    readonly property bool plainCard: !ownChrome
    // The rows' inset in the viewport: the phone's screen and the flyout pad their rows. In the card the viewport reaches
    // `bleed` px into the Stage's padding on each side (it clips the sliding pages), so a tile's remove key, a focus ring
    // or a shadow past a row's edge is not cut; the rows stay at the card's padding.
    readonly property real bleed: 10
    // W71 (the user's review, a compact flyout): the phone's screen and the flyout clip their viewport too, and their first
    // row stood at its top edge, so a focus ring drawn round a first-row tile or the back key lost its top. Their viewport
    // now reaches `edge` px out of the rows on every side as well (into their own padding, never past the panel's body).
    readonly property real edge: plainCard ? 0 : Math.min(bleed, Theme.pad)
    readonly property real rowX: plainCard ? bleed : edge + Theme.pad
    readonly property real rowY: plainCard ? bleed : edge
    // W53.3 (`[decor] quick.frame`, `quick.tiles`; data, rule 4): the card's chrome — the phone (today's) or a plain flyout
    // (the panel's material, 8 px of the look's radius, its hairline and the surfaces' elevation: 11's, the Macs') — and the
    // tiles — wide pills in two columns (today's) or compact buttons in three with the label under them (11's).
    readonly property bool flyout: !phoneStyle && Theme.decor("quick.frame", "phone") === "flyout"
    // W53.4 (`[decor] flyout.hang`): the flyout hangs from its bar — square where it meets it (`fromBottom`: the bar is under
    // it; the Stage says), its far corners rounded, the look's ground pattern across it (a Mac OS X menu extra's drop-down).
    property bool fromBottom: false
    readonly property bool hang: flyout && Theme.decor("flyout.hang", false) === true
    readonly property bool compactTiles: Theme.decor("quick.tiles", "wide") === "compact"
    // W53.5 (`quick.tiles = rows`): a config screen — one row per switch, its value at the right (QuickTile).
    readonly property bool rowTiles: Theme.decor("quick.tiles", "wide") === "rows"
    MenuStyle { id: quickMenu }
    readonly property int rowTileH: quickMenu.rowH(40)
    readonly property int tileCols: rowTiles ? 1 : (compactTiles ? 3 : 2)
    readonly property real tileW: (quick.innerW - (tileCols - 1) * Theme.gap) / tileCols
    width: parent.width
    height: flyout ? fly.implicitHeight : phoneStyle ? (phoneLoader.item ? phoneLoader.item.implicitHeight : 0)
        : plainArea.height - 2 * bleed
    // The width the rows take on the phone's screen (the flyout's inside its padding; the card's whole inner width).
    readonly property real innerW: flyout ? fly.width - 2 * fly.side - 2 * Theme.pad
        : phoneStyle ? (phoneLoader.item ? phoneLoader.item.screen.width : width) - 2 * Theme.pad : width

    // W70 (docs/ux/control-centre-modules.md): each control's state, labels, request and refusal text is its own type
    // (quick/*Control.qml), the one source a tile here, the control's bar module and its page read. The card makes one of
    // each while it is up; a tile and its page share it, so they show one request's state. Each watches its document.
    WifiControl { id: cWifi }
    AirplaneControl { id: cAir }
    BluetoothControl { id: cBt }
    FocusControl { id: cFocus }
    AudioControl { id: cAudio }
    MicControl { id: cMic }
    PowerControl { id: cPower }
    BrightnessControl { id: cBright }
    CaffeineControl { id: cCaffeine }
    NightControl { id: cNight }
    RecordControl { id: cRecord }
    DarkControl { id: cDark }
    // The card's own documents (the media row, the footer, the phone's status row and greeting) are watched while it is up.
    Watch { doc: "svc.media" }
    Watch { doc: "svc.session" }
    Watch { doc: "svc.clock" }

    readonly property string intentOrigin: "qs:quick"
    readonly property var mediaDoc: Store.docs["svc.media"] || ({})
    readonly property bool mediaPlaying: mediaDoc.playing === true && String(mediaDoc.title || "") !== ""
    readonly property bool sessionOk: (Store.docs["svc.session"] || ({})).available === true
    readonly property var clockDoc: Store.docs["svc.clock"] || ({})
    // The avatar's letter: the login name's first letter (the session's environment; nothing else knows a name yet).
    readonly property string userLetter: String(Quickshell.env("USER") || "").charAt(0).toUpperCase()
    // The greeting's part of the day, from the clock document's hour.
    readonly property string daypart: {
        var h = Number(clockDoc.hh)
        if (clockDoc.hh === undefined || isNaN(h)) return "day"
        return h < 5 ? "night" : h < 11 ? "morning" : h < 18 ? "day" : h < 22 ? "evening" : "night"
    }

    // The status sentence: the whole card in one line, each segment a link to its page.
    function statusList() {
        var out = []
        out.push({text: cWifi.statusText, page: "wifi"})
        out.push({text: cAudio.statusText, page: "audio"})
        out.push({text: cPower.statusText, page: "power"})
        if (cFocus.dnd) out.push({text: cFocus.statusText, page: "focus"})
        return out
    }
    readonly property var statusSegments: statusList()

    // ---- W70 (c): the centre is a container — `quick.tiles`, the controls it shows as tiles, in order ----
    // The setting is the daemon's (the config document); the tiles show the list in effect, and while the edit mode is on
    // the edit's own list, which Done writes as one `apply` (one undo step) and Escape or Cancel drops (the desk's edit
    // mode, K48). Nothing is written while editing. An id this frontend has no control for is left out (a newer daemon's).
    Watch { doc: "config" }
    readonly property var controls: ({
        wifi: cWifi, bluetooth: cBt, focus: cFocus, volume: cAudio, mic: cMic, power: cPower, brightness: cBright,
        caffeine: cCaffeine, nightlight: cNight, recorder: cRecord, darkmode: cDark, airplane: cAir
    })
    // W71 (c): an old name is the same control — `audio` (W70's sound output) is the one sound module `volume` now.
    readonly property var tileAliases: ({ audio: "volume" })
    // Every control that has a tile, in the order the add row offers them (the schema's choices).
    readonly property var tileChoices: ["wifi", "bluetooth", "focus", "volume", "mic", "power", "brightness", "caffeine",
        "nightlight", "recorder", "darkmode", "airplane"]
    // W71 (d, I475 8): the wide tiles — a whole row each: the sound level, the brightness, the session row. They stand
    // after the switch tiles (a row is no cell of the grid), in their own order; the edit moves them among themselves.
    readonly property var wideChoices: ["volume_level", "brightness_level", "session"]
    function isWide(id) { return wideChoices.indexOf(id) >= 0 }
    function known(id) { return controls[id] !== undefined || isWide(id) }
    readonly property var cfgTiles: {
        var v = ((Store.docs["config"] || {}).values || {})["quick.tiles"]
        return v && Array.isArray(v.value) ? v.value : null
    }
    // (until the config document is there: the schema's default; an old name read as the control's, each control once)
    readonly property var savedTiles: {
        var src = cfgTiles !== null ? cfgTiles : ["wifi", "bluetooth", "focus", "volume", "power", "brightness", "caffeine",
            "nightlight", "recorder", "darkmode", "volume_level", "brightness_level", "session"]
        var out = []
        for (var i = 0; i < src.length; i++) {
            var id = tileAliases[src[i]] || src[i]
            if (quick.known(id) && out.indexOf(id) < 0) out.push(id)
        }
        // (the switch tiles, then the wide rows: as they are drawn)
        return out.filter(function (x) { return !quick.isWide(x) }).concat(out.filter(function (x) { return quick.isWide(x) }))
    }
    // B73: an id this frontend has no tile for (a newer daemon's, a typo) is not dropped silently: the edit mode names it.
    readonly property var unknownTiles: {
        var src = cfgTiles || [], out = []
        for (var i = 0; i < src.length; i++)
            if (!quick.known(tileAliases[src[i]] || src[i]) && out.indexOf(src[i]) < 0) out.push(String(src[i]))
        return out
    }
    ListModel { id: tileModel }         // the switch tiles, in order
    ListModel { id: wideModel }         // the wide rows, in order
    property int tileRev: 0             // bumped on every change of either (what is left to add follows it)
    function tileIds() {
        var out = []
        for (var i = 0; i < tileModel.count; i++) out.push(tileModel.get(i).mid)
        return out
    }
    function wideIds() {
        var out = []
        for (var i = 0; i < wideModel.count; i++) out.push(wideModel.get(i).mid)
        return out
    }
    // The whole list as `quick.tiles` has it: the switch tiles, then the wide rows.
    function allIds() { return tileIds().concat(wideIds()) }
    function setTiles(list) {
        if (JSON.stringify(allIds()) === JSON.stringify(list)) return
        tileModel.clear()
        wideModel.clear()
        for (var i = 0; i < list.length; i++) (isWide(list[i]) ? wideModel : tileModel).append({ mid: list[i] })
        tileRev++
    }
    onSavedTilesChanged: if (!editing) setTiles(savedTiles)
    readonly property var addable: {
        var rev = tileRev, ids = allIds()
        return tileChoices.concat(wideChoices).filter(function (id) { return ids.indexOf(id) < 0 })
    }
    function nameOf(id) { return controls[id] ? controls[id].label : I18n.tr("layout.module." + id) }

    property bool editing: false
    property string editError: ""
    onEditingChanged: {
        if (!editing) setTiles(savedTiles)
        if (testLog) { console.log("quick-edit " + (editing ? "on" : "off")); logTimer.restart() }
    }
    function focusTile(i) {
        Qt.callLater(function () {
            var n = coreTiles.count
            if (n === 0) { if (addRow.visible) addRow.focusFirst(); return }
            var t = coreTiles.itemAt(Math.max(0, Math.min(n - 1, i)))
            if (t) t.forceActiveFocus()
        })
    }
    function startEdit() {
        if (editing) return
        if (page !== "") closePage()
        editError = ""
        editing = true
        focusTile(0)
    }
    function cancelEdit() {
        if (!editing) return
        editError = ""
        editing = false
        Qt.callLater(function () { editKey.forceActiveFocus() })
    }
    function moveTile(from, to) {
        if (!editing || from === to || to < 0 || to >= tileModel.count) return
        tileModel.move(from, to, 1)
        tileRev++
        focusTile(to)
    }
    function removeTile(i) {
        if (!editing || i < 0 || i >= tileModel.count) return
        tileModel.remove(i, 1)
        tileRev++
        focusTile(i)
    }
    function addTile(id) {
        if (!editing || !known(id) || allIds().indexOf(id) >= 0) return
        (isWide(id) ? wideModel : tileModel).append({ mid: id })
        tileRev++
    }
    // The wide rows: moved among themselves (Alt with Up or Down, a drag), taken out by their remove key or Delete.
    function focusWide(i) {
        Qt.callLater(function () {
            var n = wideRows.count
            if (n === 0) { focusTile(tileModel.count - 1); return }
            var t = wideRows.itemAt(Math.max(0, Math.min(n - 1, i)))
            if (t) t.forceActiveFocus()
        })
    }
    function moveWide(from, to) {
        if (!editing || from === to || to < 0 || to >= wideModel.count) return
        wideModel.move(from, to, 1)
        tileRev++
        focusWide(to)
    }
    function removeWide(i) {
        if (!editing || i < 0 || i >= wideModel.count) return
        wideModel.remove(i, 1)
        tileRev++
        focusWide(i)
    }
    function dragWide(from, ay) {
        var to = from
        for (var i = 0; i < wideRows.count; i++) {
            var r = wideRows.itemAt(i)
            if (r && ay >= r.y && ay < r.y + r.height) to = i
        }
        moveWide(from, to)
    }
    // A drag: the tile under the pointer's cell takes the dragged tile's place as the pointer reaches it.
    function dragTile(from, ax, ay, cellH) {
        var col = Math.max(0, Math.min(grid.columns - 1, Math.floor(ax / (tileW + grid.spacing))))
        var row = Math.max(0, Math.floor(ay / (cellH + grid.spacing)))
        moveTile(from, Math.min(tileModel.count - 1, row * grid.columns + col))
    }
    function saveEdit() {
        if (!editing) return
        var now = allIds()
        if (JSON.stringify(now) === JSON.stringify(savedTiles)) { cancelEdit(); return }
        editError = ""
        if (Quickshell.env("KURASHI_QUICK_LOG") === "1") console.log("quick-save " + JSON.stringify(now))
        Store.apply([{ set: "quick.tiles", value: now }], function (errors) {
            if (!errors || errors.length === 0) { editing = false; Qt.callLater(function () { editKey.forceActiveFocus() }); return }
            var c = String(errors[0].code || "")
            editError = c === "disconnected" ? I18n.tr("quick.edit.disconnected")
                : I18n.tr("quick.edit.refused") + (c !== "" && I18n.tr(c) !== c ? " (" + I18n.tr(c) + ")" : "")
        })
    }
    // Test only (KURASHI_QUICK_LOG=1, frontend/test-quick-modules.sh): the tiles shown, in order, and where the edit's keys
    // stand on the output (`quick-at <name> x y w h`), a moment after each change (the card's own motion first).
    readonly property bool testLog: Quickshell.env("KURASHI_QUICK_LOG") === "1"
    onTileRevChanged: if (testLog) { console.log("quick-tiles " + allIds().join(",")); logTimer.restart() }
    readonly property var qsWin: Window.window ? QsWindow.window : null
    function logAt(name, item) {
        if (!item || !item.visible || qsWin === null) return
        var o = Light.originOf(qsWin), p = item.mapToItem(null, 0, 0)
        console.log("quick-at " + name + " " + [o.x + p.x, o.y + p.y, item.width, item.height].map(Math.round).join(" "))
    }
    Timer {
        id: logTimer
        interval: 700
        onTriggered: {
            quick.logAt("edit", editKey)
            quick.logAt("done", doneKey)
            for (var i = 0; i < addKeys.count; i++) { var b = addKeys.itemAt(i); if (b) quick.logAt("add:" + b.modelData, b) }
            for (var j = 0; j < coreTiles.count; j++) { var t = coreTiles.itemAt(j); if (t) quick.logAt("tile:" + t.mid, t) }
            for (var w = 0; w < wideRows.count; w++) { var r = wideRows.itemAt(w); if (r) quick.logAt("tile:" + r.mid, r) }
            quick.logAt("media", mediaRow)
            // W71: what clips the rows (the viewport) and what has the keyboard, so a suite can read a focus ring whole.
            quick.logAt("viewport", viewport)
            if (quick.Window.activeFocusItem) quick.logAt("focus", quick.Window.activeFocusItem)
        }
    }
    // (and after a page turn or a focus move)
    onShownPageChanged: if (testLog) { console.log("quick-page " + (shownPage !== "" ? shownPage : "tiles")); logTimer.restart() }
    Connections {
        target: quick.testLog ? quick.Window.window : null
        function onActiveFocusItemChanged() { logTimer.restart() }
    }
    // Test only (KURASHI_QUICK_FOCUS=first|last): the first or the last tile takes the keyboard focus when the card opens,
    // so a screenshot on nested niri (whose virtual keyboard does not reach a layer surface) shows the focus ring.
    readonly property string testFocus: Quickshell.env("KURASHI_QUICK_FOCUS") || ""
    // Test only (KURASHI_QUICK_PAGE=<page>): the card opens on that page, as a tile's arrow would (shots of each card).
    readonly property string testPage: navOwned ? (Quickshell.env("KURASHI_QUICK_PAGE") || "") : ""

    // Pages: one page at a time, slid in from the right; the tiles slide out to the left.
    // The page the card opens on: the power and bluetooth faces' expanded views (Stage, I44). "" opens on the tiles.
    property string startPage: ""
    property string page: ""           // the page asked for; "" shows the tiles
    property string shownPage: ""      // the page the pane holds; kept while it slides out
    property var returnTo: null        // the control that opened the page: focus goes back there
    property real slide: 0             // 0 the tiles, 1 the page
    readonly property bool tilesShown: page === "" || slide < 1

    function openPage(name, from) {
        if (editing) cancelEdit()   // (a module's ask while editing: the page wins, the unsaved edit is dropped)
        returnTo = from
        page = name
    }
    function closePage() {
        var back = returnTo
        returnTo = null
        page = ""
        if (back !== null) back.forceActiveFocus()
    }
    // A tile without a page of its own (keep awake, record, dark mode): its right click or Menu key opens the Settings page
    // that holds its setting. The daemon checks the page id; nothing waits for the answer, and a refusal shows nowhere.
    function openSettings(page) {
        Store.act("settings.open", {page: page}, function () {})
    }
    // W71: the module whose click or hover opened the page shown ("" when the card got there itself: a tile, the status
    // line, Back). Its page lists that module's options (its click among them), and Esc closes the card (I475 7: the user
    // came for that control, not for the tiles); a page the tiles opened goes back to them.
    readonly property string pageBy: page !== "" && navOwned ? QuickNav.by : ""
    // (a shared page lists the options of the module that opened it: the microphone's on the sound page)
    readonly property var pageOptions: pageBy !== "" ? [pageBy] : []
    onPageChanged: {
        if (page !== "") shownPage = page
        if (navOwned) QuickNav.showing(page, navTurn)
        navTurn = false
        slideAnim.stop()
        slideAnim.to = page !== "" ? 1 : 0
        slideAnim.start()
    }
    NumberAnimation {
        id: slideAnim
        target: quick
        property: "slide"
        // A spring (K42): the page arrives with the theme's overshoot; motion off keeps the plain curve.
        duration: Theme.emphMs + (Theme.springOn ? 60 : 0)
        easing.type: Theme.springOn ? Easing.OutBack : Easing.BezierSpline
        easing.overshoot: Theme.overshoot
        easing.bezierCurve: Theme.enterCurve
        onFinished: if (quick.page === "") quick.shownPage = ""
    }
    // W70: a control's bar module opens the card on its page (QuickNav, the stand-in for CONTRACT-CHANGE row 710): the card
    // takes the page it was asked for when it is made, turns to the page a module asks for while it is up, and says which
    // page it shows (a module draws itself pressed while its page is up). Only the quick card does: the power and Bluetooth
    // faces' views (`startPage`) open where the Stage says.
    property bool navOwned: false
    property bool navTurn: false        // the page change under way is a module's ask
    Connections {
        target: QuickNav
        enabled: quick.navOwned
        function onSerialChanged() {
            var p = QuickNav.take()
            if (p === "" || p === quick.page) return
            quick.navTurn = true
            quick.openPage(p, null)
        }
    }
    Component.onDestruction: if (navOwned && QuickNav.shown === page) QuickNav.showing("", false)
    Component.onCompleted: {
        setTiles(savedTiles)
        syncTiles()
        navOwned = startPage === ""
        if (navOwned) {
            startPage = QuickNav.take()
            navTurn = startPage !== ""
            QuickNav.showing(startPage, navTurn)
        }
        if (startPage !== "") {
            page = startPage
            shownPage = startPage
            slideAnim.stop()    // it opens on the page: no slide in from the tiles
            slide = 1
        } else if (testPage !== "") {
            page = testPage
            shownPage = testPage
            slideAnim.stop()
            slide = 1
        } else if (testFocus === "first" || testFocus === "last") {
            Qt.callLater(function () { quick.focusTile(quick.testFocus === "first" ? 0 : coreTiles.count - 1) })
        }
    }
    // Esc and Left go back from a page (a slider takes Left for itself). On the tiles they pass on, to close the card; on a
    // page a module opened (W71, I475 7) Esc passes on too: the card closes, Left still goes back to the tiles.
    Keys.onPressed: event => {
        if (quick.editing && event.key === Qt.Key_Escape) {
            quick.cancelEdit()
            event.accepted = true
            return
        }
        if (quick.page === "") return
        if (event.key === Qt.Key_Escape && quick.pageBy !== "") return
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left) {
            quick.closePage()
            event.accepted = true
        }
    }

    // The `quick.tiles` contributions (K28, W18). The host lays nothing out: the grid places one cell per entry (above), so
    // the mod tiles take the core tiles' flow and no space of their own. Watches runtime.slots while the card is up (Ma).
    SlotHost {
        id: tileSlot
        slot: "quick.tiles"
        layout: "cells"
        cellWidth: quick.tileW
        cellHeight: quick.rowTiles ? quick.rowTileH : (quick.compactTiles ? 78 : 56)
    }
    // The core tiles are the first `coreCount` cells; the contributions follow.
    readonly property int coreCount: coreTiles.count
    // The contributions the cells show. runtime.slots changes for every slot, so the host's `entries` is a new array each
    // time: a Repeater over it would rebuild every mod cell, and the focused one with it. The list changes only when a
    // contribution appears, leaves or changes (its file or reason); then the focus stays on its tile, or moves to the tile
    // before it when that one is gone (W37, I86).
    property var tileList: []
    function sameTiles(a, b) {
        if (a.length !== b.length) return false
        for (var i = 0; i < a.length; i++)
            if (a[i].qml !== b[i].qml || a[i].reason !== b[i].reason) return false
        return true
    }
    function syncTiles() {
        var next = tileSlot.entries
        if (sameTiles(tileList, next)) return
        var cells = tileCells()
        var at = -1
        for (var k = 0; k < cells.length; k++) if (cells[k] !== null && cells[k].activeFocus) at = k
        var key = at >= coreCount && at - coreCount < tileList.length ? tileList[at - coreCount].qml : ""
        tileList = next
        if (at >= 0) Qt.callLater(function () { quick.refocus(at, key) })
    }
    function refocus(at, key) {
        var cells = tileCells()
        var to = -1
        if (key !== "") {
            for (var i = 0; i < tileList.length; i++) if (tileList[i].qml === key) to = coreCount + i
        }
        if (to < 0) {   // the same place, or the tile before it (a cell is a tile or null)
            to = Math.min(at, cells.length - 1)
            while (to > 0 && cells[to] === null) to--
        }
        if (to >= 0 && cells[to] !== null) cells[to].forceActiveFocus()
    }
    Connections {
        target: tileSlot
        function onEntriesChanged() { quick.syncTiles() }
    }
    // The grid's cells in visual order: the core tiles, then one per contribution. A cell that is not a tile (a plain
    // contribution) is null, so the arrows keep their places and never land on it.
    function tileCells() {
        var out = []
        for (var c = 0; c < coreTiles.count; c++) out.push(coreTiles.itemAt(c))
        for (var i = 0; i < modCells.count; i++) {
            var cell = modCells.itemAt(i)
            var t = cell !== null ? cell.tile : null
            out.push(t !== null && t !== undefined && t.isTile === true ? t : null)
        }
        return out
    }

    // The page pane: one page loaded at a time, and only while it is shown (its Watch runs only then).
    Component {
        id: wifiC
        WifiPage {
            live: quick.page === "wifi"
            wifiReq: cWifi.req
            airReq: cAir.req
            joinReq: cWifi.joinReq
            optionIds: quick.pageOptions
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: btC
        BluetoothPage { optionIds: quick.pageOptions; onBackRequested: quick.closePage() }
    }
    Component {
        id: focusC
        FocusPage {
            dndReq: cFocus.req
            optionIds: quick.pageOptions
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: audioC
        AudioPage {
            soundReq: cAudio.req
            sinkReq: cAudio.sinkReq
            micReq: cMic.req
            srcReq: cMic.sourceReq
            optionIds: quick.pageOptions
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: powerC
        PowerPage {
            profReq: cPower.profileReq
            optionIds: quick.pageOptions
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: displayC
        DisplayPage { optionIds: quick.pageOptions; onBackRequested: quick.closePage() }
    }
    Component {
        id: nightC
        NightPage {
            nightReq: cNight.req
            optionIds: quick.pageOptions
            onBackRequested: quick.closePage()
        }
    }
    // W71 (I475 3): keep awake and dark mode have pages of their own now (a click on their module opens them).
    Component {
        id: caffeineC
        CaffeinePage { ctl: cCaffeine; onBackRequested: quick.closePage() }
    }
    Component {
        id: darkC
        ControlPage { ctl: cDark; onBackRequested: quick.closePage() }
    }

    // ---- the phone ----
    Loader {
        id: phoneLoader
        // B73: made only while the centre is a phone (it was always made, invisible, in the card style; Ma)
        active: quick.phoneStyle
        width: quick.width
        sourceComponent: Component {
            PhoneFrame {
                id: phone
                theme: Theme
                width: quick.width
                contentHeight: (quick.shownPage !== "" ? pageLoader.height : tilesPane.height) + Theme.pad
                // The status row: the time on the left; on the right the network, Do not disturb while it is on, and the battery
                // — only from the documents the card watches (nothing is polled), and nothing for a service that is not there.
                statusLeft: Text {
                    height: phone.statusH
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: Theme.fsLabel
                    font.weight: Theme.wBold
                    font.family: Theme.fam(text, Theme.families)
                    text: quick.clockDoc.hh !== undefined ? quick.clockDoc.hh + ":" + quick.clockDoc.mm : ""
                }
                statusRight: [
                    Icon {
                        visible: cFocus.dnd
                        height: phone.statusH
                        name: "do_not_disturb_on"
                        glyph: "☾"
                        filled: true
                        size: 15
                    },
                    Icon {
                        visible: cWifi.ok
                        height: phone.statusH
                        name: cWifi.glanceIcon
                        glyph: cWifi.glanceGlyph
                        filled: true
                        size: 15
                    },
                    Icon {
                        visible: cPower.battery
                        height: phone.statusH
                        name: cPower.batteryIcon
                        glyph: "▮"
                        filled: true
                        size: 15
                    },
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        visible: cPower.battery
                        height: phone.statusH
                        verticalAlignment: Text.AlignVCenter
                        color: Theme.fg
                        font.pixelSize: Theme.fsCaption
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: cPower.battery ? cPower.percent + "%" : ""
                    }
                ]

            }
        }
    }

    // The screen's content: the tiles and the page side by side, sliding inside the screen.
    Item {
        id: viewport
        // (the flyout's area under `quick.frame = flyout`, the phone's screen under `quick.style = phone`, else the card's)
        parent: quick.flyout ? flyArea : quick.phoneStyle && phoneLoader.item ? phoneLoader.item.area : plainArea
        x: -quick.edge
        y: -quick.edge
        width: parent.width + 2 * quick.edge
        height: parent.height + 2 * quick.edge
        clip: true

        Column {
            id: tilesPane
            width: quick.innerW
            spacing: Theme.gap
            x: quick.rowX - quick.slide * viewport.width
            y: quick.rowY
            visible: quick.tilesShown

            // The greeting row (SekaiPop's user row): an avatar key, the time of day's greeting and the card's name.
            Item {
                id: hello
                // (the phone's own: a flyout has no greeting row, as 11's has none, and the card has its title)
                visible: quick.phoneStyle
                width: quick.innerW
                height: avatar.height
                Accessible.role: Accessible.Heading
                Accessible.name: I18n.tr("island.quick.heading")
                Block {
                    id: avatar
                    width: 44
                    height: 44 + Theme.shadowDy
                    radius: Theme.rFull
                    fill: Theme.selected
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        visible: quick.userLetter !== ""
                        anchors.centerIn: parent
                        color: Theme.color("color.on_selected", Theme.fg)
                        font.pixelSize: Theme.fsTitle + 4
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: quick.userLetter
                    }
                    Icon {
                        visible: quick.userLetter === ""
                        anchors.centerIn: parent
                        name: "person"
                        glyph: "◡"
                        filled: true
                        size: 24
                        color: Theme.color("color.on_selected", Theme.fg)
                    }
                }
                Column {
                    x: avatar.width + Theme.gap + 2
                    width: hello.width - x
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -Theme.shadowDy / 2
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.pixelSize: Theme.fsTitle
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("frontend.quick.greeting." + quick.daypart)
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        width: parent.width
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("island.quick.heading")
                    }
                }
            }
            QuickStatus {
                id: statusLine
                visible: !quick.flyout
                width: quick.innerW
                segments: quick.statusSegments
                onOpened: (target, from) => quick.openPage(target, from)
            }
            Grid {
                id: grid
                width: quick.innerW
                columns: quick.tileCols
                spacing: quick.rowTiles ? 0 : Theme.gap
                // Up and Down move within a column, Left and Right between the two columns; Right on a tile opens its page.
                // The cells are quick.tileCells(): the core tiles, then the contributions (a plain contribution's cell is null).
                // W70: in the edit mode Alt with an arrow moves the focused tile (a row up or down, a place left or right) and
                // Delete or Backspace takes it out; the plain arrows still move the focus.
                Keys.onPressed: event => {
                    var cells = quick.tileCells()
                    var i = -1
                    for (var k = 0; k < cells.length; k++) if (cells[k] !== null && cells[k].activeFocus) i = k
                    if (i < 0) return
                    if (quick.editing && i < quick.coreCount) {
                        var alt = (event.modifiers & Qt.AltModifier) !== 0
                        var by = event.key === Qt.Key_Up ? -grid.columns : event.key === Qt.Key_Down ? grid.columns
                            : event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : 0
                        if (alt && by !== 0) {
                            quick.moveTile(i, Math.max(0, Math.min(quick.coreCount - 1, i + by)))
                            event.accepted = true
                            return
                        }
                        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                            quick.removeTile(i)
                            event.accepted = true
                            return
                        }
                    }
                    var to = -1
                    switch (event.key) {
                    case Qt.Key_Up: to = i >= grid.columns ? i - grid.columns : -1; break
                    case Qt.Key_Down: to = i + grid.columns < cells.length ? i + grid.columns : -1; break
                    case Qt.Key_Left: to = i % grid.columns > 0 ? i - 1 : -1; break
                    case Qt.Key_Right: to = i % grid.columns < grid.columns - 1 ? i + 1 : -1; break
                    default: return
                    }
                    if (to >= 0 && cells[to] !== null) cells[to].forceActiveFocus()
                    event.accepted = true
                }

                // W70: each tile is drawn from its control (quick/*Control.qml), in the order of `quick.tiles` (the edit's
                // order while editing); the page it opens is the control's, a tile without one opens its Settings page.
                // K47 (docs/ux/power.md): a missing program, protocol or compositor is the tile's reason, never a dead tile.
                Repeater {
                    id: coreTiles
                    model: tileModel
                    delegate: ControlTile {
                        id: ctile
                        required property string mid
                        required property int index
                        width: quick.tileW
                        ctl: quick.controls[mid] || null
                        editing: quick.editing
                        dragArea: grid
                        onPageRequested: quick.openPage(ctl.page, ctile)
                        onSecondaryRequested: quick.openSettings(ctl.settingsPage)
                        onRemoveRequested: quick.removeTile(index)
                        onDragTo: (ax, ay) => quick.dragTile(index, ax, ay, height)
                    }
                }
                // K28 `quick.tiles` (W18): one cell per ready contribution, after the core tiles, in the same 2-column flow. A
                // cell is a tile's size (SlotHost's cell: half the card less the gap, 56 px) and clips what is not a tile.
                Repeater {
                    id: modCells
                    model: quick.tileList
                    delegate: tileSlot.cell
                }
            }

            // W70 (c): the edit key under the tiles (a Tab stop after them), and while editing the edit's own rows: what it
            // does, the controls to add, Done and Cancel, and a refusal.
            Item {
                width: quick.innerW
                height: editKey.height
                visible: !quick.editing
                IconButton {
                    id: editKey
                    anchors.right: parent.right
                    icon: "edit"
                    glyph: "✎"
                    a11y: I18n.tr("quick.edit.open")
                    onClicked: quick.startEdit()
                }
            }
            // W71 (d, I475 8): the wide rows of `quick.tiles` — the levels and the session row, there by default — after
            // the edit key (the Tab order of before: the tiles, the edit key, the levels). In the edit mode Alt with Up or
            // Down moves the focused row, Delete or Backspace takes it out. The flyout's own footer band holds the session
            // keys, so the session row is not drawn there (Shōjiki: once).
            Column {
                id: wideCol
                width: quick.innerW
                spacing: Theme.gap
                visible: wideRows.count > 0
                Keys.onPressed: event => {
                    if (!quick.editing) return
                    var i = -1
                    for (var k = 0; k < wideRows.count; k++) { var r = wideRows.itemAt(k); if (r && r.activeFocus) i = k }
                    if (i < 0) return
                    var alt = (event.modifiers & Qt.AltModifier) !== 0
                    if (alt && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                        quick.moveWide(i, i + (event.key === Qt.Key_Up ? -1 : 1))
                        event.accepted = true
                    } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                        quick.removeWide(i)
                        event.accepted = true
                    } else if (!alt && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                        var to = i + (event.key === Qt.Key_Up ? -1 : 1)
                        if (to < 0) quick.focusTile(tileModel.count - 1)
                        else if (to < wideRows.count) wideRows.itemAt(to).forceActiveFocus()
                        event.accepted = true
                    }
                }
                Repeater {
                    id: wideRows
                    model: wideModel
                    delegate: WideTile {
                        id: wrow
                        required property string mid
                        required property int index
                        kind: mid
                        width: quick.innerW
                        visible: shown && !(quick.flyout && mid === "session" && !quick.editing)
                        height: visible ? implicitHeight : 0
                        audio: cAudio
                        bright: cBright
                        sessionOk: quick.sessionOk
                        editing: quick.editing
                        dragArea: wideCol
                        intentOrigin: quick.intentOrigin
                        onPageRequested: (p, from) => quick.openPage(p, from)
                        onRemoveRequested: quick.removeWide(index)
                        onDragTo: (ax, ay) => quick.dragWide(index, ay)
                    }
                }
            }
            Column {
                id: editRows
                width: quick.innerW
                visible: quick.editing
                spacing: Theme.gap
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr(quick.addable.length > 0 ? "quick.edit.hint" : "quick.edit.hint_full")
                }
                // B73: what `quick.tiles` names that this shell has no tile for, said once (it is kept in the list).
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    visible: quick.unknownTiles.length > 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("quick.edit.unknown").replace("{ids}", quick.unknownTiles.join(", "))
                }
                // The controls not in the centre: one key each, a press adds it at the end.
                Flow {
                    id: addRow
                    width: parent.width
                    spacing: Theme.gap
                    visible: quick.addable.length > 0
                    function focusFirst() { var b = addKeys.itemAt(0); if (b) b.forceActiveFocus() }
                    Repeater {
                        id: addKeys
                        model: quick.editing ? quick.addable : []
                        delegate: Button {
                            required property string modelData
                            label: "+ " + quick.nameOf(modelData)
                            onClicked: quick.addTile(modelData)
                        }
                    }
                }
                Row {
                    spacing: Theme.gap
                    layoutDirection: Qt.RightToLeft
                    width: parent.width
                    Button {
                        id: doneKey
                        primary: true
                        label: I18n.tr("quick.edit.done")
                        onClicked: quick.saveEdit()
                    }
                    Button {
                        label: I18n.tr("quick.edit.cancel")
                        onClicked: quick.cancelEdit()
                    }
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    antialiasing: !Theme.pixelType
                    font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                    visible: quick.editError !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: quick.editError
                }
            }

            Loader {
                id: mediaRow
                width: quick.innerW
                visible: quick.mediaPlaying
                active: quick.mediaPlaying
                sourceComponent: Component {
                    QuickMedia {
                        width: quick.innerW
                        d: quick.mediaDoc
                        // The island's media view: its expanded card, with the transport in it.
                        onOpenRequested: Store.act("island.expand")
                    }
                }
            }
        }

        Loader {
            id: pageLoader
            width: quick.innerW
            x: quick.rowX + (1 - quick.slide) * viewport.width
            y: quick.rowY
            active: quick.shownPage !== ""
            sourceComponent: quick.shownPage === "wifi" ? wifiC
                : quick.shownPage === "bluetooth" ? btC
                : quick.shownPage === "focus" ? focusC
                : quick.shownPage === "audio" ? audioC
                : quick.shownPage === "power" ? powerC
                : quick.shownPage === "display" ? displayC
                : quick.shownPage === "night" ? nightC
                : quick.shownPage === "caffeine" ? caffeineC
                : quick.shownPage === "dark" ? darkC : null
            // The page's first control takes the focus once it exists (after the Loader has made it).
            onStatusChanged: if (status === Loader.Ready && item !== null)
                Qt.callLater(function () { if (pageLoader.item !== null) pageLoader.item.focusFirst() })
        }
    }

    // ---- the card (W70 d): the rows straight in the Stage's card, which draws the chrome ----
    Item {
        id: plainArea
        visible: quick.plainCard
        x: -quick.bleed
        y: -quick.bleed
        width: quick.width + 2 * quick.bleed
        height: quick.plainCard ? (quick.shownPage !== "" ? pageLoader.height : tilesPane.height) + 2 * quick.bleed : 0
    }

    // ---- the flyout (W53.3, `quick.frame = flyout`): the panel's material in the look's radius with its hairline, over
    // the surfaces' elevation; the tiles and pages inside its padding, and a footer band — the battery on the left, Settings
    // and the session menu on the right (11's footer; it has no tile editor here, so no edit key: Shōjiki). Made only then.
    Item {
        id: fly
        visible: quick.flyout
        width: quick.width
        // Room round the body for its shadow (a clipping card would cut it off).
        readonly property real side: quick.flyout ? 12 : 0
        // A hanging flyout keeps no shadow room on its bar's side (it meets the bar there).
        readonly property real sideTop: quick.hang && !quick.fromBottom ? 0 : side
        readonly property real sideBottom: quick.hang && quick.fromBottom ? 0 : side
        readonly property real rTop: quick.hang && !quick.fromBottom ? 0 : Theme.rLg
        readonly property real rBottom: quick.hang && quick.fromBottom ? 0 : Theme.rLg
        readonly property real footH: 52
        implicitHeight: quick.flyout
            ? sideTop + sideBottom + Theme.pad + (quick.shownPage !== "" ? pageLoader.height : tilesPane.height) + Theme.pad + footH : 0
        Loader {
            active: quick.flyout
            anchors.fill: parent
            anchors { leftMargin: fly.side; rightMargin: fly.side; topMargin: fly.sideTop; bottomMargin: fly.sideBottom }
            sourceComponent: Item {
                Elevation { anchors.fill: parent; radius: Theme.rLg; level: 3; cutTop: fly.rTop === 0; cutBottom: fly.rBottom === 0 }
                Rectangle {
                    anchors.fill: parent
                    topLeftRadius: fly.rTop
                    topRightRadius: fly.rTop
                    bottomLeftRadius: fly.rBottom
                    bottomRightRadius: fly.rBottom
                    color: Theme.panel
                    border.width: 1
                    border.color: Theme.color("color.outline_variant", "#e5e5e5")
                    Pattern { anchors.fill: parent; radius: Math.max(fly.rTop, fly.rBottom) }
                }
                // W53.5: the look's banded fill and frame (an RPG window, the PS2's glow line); nothing without them.
                Loader {
                    anchors.fill: parent
                    active: Theme.frame !== "" || Theme.fillBands > 1
                    sourceComponent: PanelDress { radius: Theme.rLg; alpha: Theme.panel.a; frame: false }
                }
                Loader {
                    z: 2
                    anchors.fill: parent
                    active: Theme.frame !== ""
                    sourceComponent: PanelDress { radius: Theme.rLg; bands: false }
                }
                // The footer band: the ground a step deeper, a hairline above it, the lower corners the flyout's.
                Rectangle {
                    x: 1
                    y: parent.height - fly.footH
                    width: parent.width - 2
                    height: fly.footH - 1
                    bottomLeftRadius: Math.max(0, fly.rBottom - 1)
                    bottomRightRadius: Math.max(0, fly.rBottom - 1)
                    color: Qt.alpha(Theme.surface, 0.55)
                    Rectangle { width: parent.width; height: 1; color: Theme.color("color.outline_variant", "#e5e5e5") }
                    Row {
                        x: Theme.pad + 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        visible: cPower.battery
                        Icon { name: cPower.batteryIcon; glyph: "▮"; size: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.fg
                            font.pixelSize: Theme.fsLabel
                            font.family: Theme.fam(text, Theme.families)
                            text: cPower.battery ? cPower.percent + " %" : ""
                        }
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: Theme.pad; verticalCenter: parent.verticalCenter }
                        spacing: 4
                        IconButton {
                            icon: "settings"
                            glyph: "⚙"
                            a11y: I18n.tr("action.settings.open")
                            onClicked: quick.openSettings("")
                        }
                        IconButton {
                            icon: "power_settings_new"
                            glyph: "⏻"
                            a11y: I18n.tr("island.quick.session.power_menu")
                            onClicked: Store.act("session.menu", {})
                        }
                    }
                }
            }
        }
        Item {
            id: flyArea
            // (the whole inner width: the tiles stand `Theme.pad` in from it, as on the phone's screen)
            x: fly.side
            y: fly.sideTop + Theme.pad
            width: Math.max(0, fly.width - 2 * fly.side)
            height: Math.max(0, fly.implicitHeight - fly.sideTop - fly.sideBottom - 2 * Theme.pad - fly.footH)
        }
    }
}
