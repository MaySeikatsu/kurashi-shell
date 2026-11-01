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
// watches what it lists only while it is on screen. Requests are owned here, so a tile and its page show one state.
// W21 (K42, SekaiPop's "the control center is a phone"): the card is a phone (PhoneFrame) — a status row with the time and
// the glyphs of what the card already watches, a greeting row, keycap tiles and pill levels; the pages slide inside the
// screen. The phone is the card's own chrome (`ownChrome`): the Stage draws no card background around it.
Item {
    id: quick
    readonly property bool ownChrome: true
    // W53.3 (`[decor] quick.frame`, `quick.tiles`; data, rule 4): the card's chrome — the phone (today's) or a plain flyout
    // (the panel's material, 8 px of the look's radius, its hairline and the surfaces' elevation: 11's, the Macs') — and the
    // tiles — wide pills in two columns (today's) or compact buttons in three with the label under them (11's).
    readonly property bool flyout: Theme.decor("quick.frame", "phone") === "flyout"
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
    height: flyout ? fly.implicitHeight : phone.implicitHeight
    // The width the rows take on the phone's screen (the flyout's inside its padding).
    readonly property real innerW: flyout ? fly.width - 2 * fly.side - 2 * Theme.pad : phone.screen.width - 2 * Theme.pad

    // Documents: the card's own (the tiles, the status, the levels) are watched while it is up.
    Watch { doc: "svc.network" }
    Watch { doc: "svc.audio" }
    Watch { doc: "svc.power" }
    Watch { doc: "svc.bluetooth" }
    Watch { doc: "svc.brightness" }
    Watch { doc: "svc.notifications" }
    Watch { doc: "svc.media" }
    Watch { doc: "svc.session" }
    Watch { doc: "svc.clock" }
    // K47 (W23-system): the caffeine, night light and record tiles.
    Watch { doc: "svc.idle" }
    Watch { doc: "svc.nightlight" }
    Watch { doc: "svc.recorder" }

    readonly property string intentOrigin: "qs:quick"
    readonly property var netDoc: Store.docs["svc.network"] || ({})
    readonly property bool netOk: typeof netDoc.state === "string" && netDoc.state !== "unavailable"
    readonly property bool wifiOn: netDoc.wifi_enabled === true
    readonly property var primary: netDoc.primary || null
    readonly property string primaryName: primary ? String(primary.name || "") : ""
    readonly property var btDoc: Store.docs["svc.bluetooth"] || ({})
    readonly property bool btOk: btDoc.available === true
    readonly property var audioDoc: Store.docs["svc.audio"] || ({})
    readonly property bool audioOk: audioDoc.available === true
    readonly property bool muted: audioDoc.muted === true
    readonly property var sinkDef: defaultOf(audioOk ? audioDoc.sinks : null)
    readonly property var srcDef: audioOk && audioDoc.source ? audioDoc.source : null
    readonly property string sinkName: sinkDef ? String(sinkDef.description || sinkDef.name || "") : ""
    readonly property int volPct: Math.round(Number(audioDoc.volume || 0) * 100)
    readonly property var powerDoc: Store.docs["svc.power"] || ({})
    readonly property bool powerOk: powerDoc.available === true
    readonly property bool battery: powerDoc.present === true && powerDoc.percent !== undefined
    readonly property var brDoc: Store.docs["svc.brightness"] || ({})
    readonly property bool brOk: brDoc.present === true
    readonly property real brLevel: brOk ? Math.max(0, Math.min(1, Number(brDoc.percent || 0) / 100)) : 0
    readonly property var notesDoc: Store.docs["svc.notifications"] || ({})
    readonly property bool notifyOk: Store.docs["svc.notifications"] !== undefined
    readonly property bool dnd: notesDoc.dnd === true
    readonly property bool dndTimed: typeof notesDoc.dnd_until === "number"
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
    // The status row's network mark: [Material Symbols name, text glyph] for the primary link, or the radio's state.
    readonly property var netGlyph: !wifiOn && primary === null ? ["wifi_off", "≋"]
        : primary === null ? ["signal_wifi_0_bar", "≋"]
        : primary.kind === "ethernet" ? ["lan", "⇄"]
        : primary.kind === "vpn" ? ["vpn_key", "⚿"]
        : ["wifi", "≋"]
    // The battery's mark in seven steps, or charging.
    readonly property string batteryIcon: !battery ? ""
        : String(powerDoc.state || "") === "charging" ? "battery_charging_full"
        : Number(powerDoc.percent) >= 95 ? "battery_full"
        : "battery_" + Math.max(0, Math.min(6, Math.floor(Number(powerDoc.percent) / 100 * 7))) + "_bar"
    // K47 (docs/ux/power.md): idle (caffeine), night light, the recorder. A missing program or protocol is a reason.
    readonly property var idleDoc: Store.docs["svc.idle"] || ({})
    readonly property bool idleOk: Store.docs["svc.idle"] !== undefined
    readonly property bool caffeine: idleDoc.caffeine === true
    readonly property var nightDoc: Store.docs["svc.nightlight"] || ({})
    readonly property bool nightOk: Store.docs["svc.nightlight"] !== undefined
    readonly property var recDoc: Store.docs["svc.recorder"] || ({})
    readonly property bool recOk: Store.docs["svc.recorder"] !== undefined
    readonly property bool recording: recDoc.recording === true
    readonly property string caffeineValue: caffeine ? I18n.tr("power.quick.caffeine.on")
        : idleDoc.enabled === false ? I18n.tr("power.quick.caffeine.idle_off")
        : idleDoc.inhibited === true && (idleDoc.inhibitors || []).length > 0
            ? I18n.tr("power.quick.caffeine.kept_by").replace("{who}", String(idleDoc.inhibitors[0].who || ""))
        : I18n.tr("island.quick.off")
    readonly property string nightValue: nightDoc.enabled !== true ? I18n.tr("island.quick.off")
        : String(nightDoc.schedule || "") === "always" ? I18n.tr("island.quick.on")
        : nightDoc.active === true
            ? (nightDoc.next_change ? I18n.tr("island.quick.tile.until").replace("{t}", String(nightDoc.next_change)) : I18n.tr("island.quick.on"))
        : nightDoc.next_change ? I18n.tr("power.quick.night.from").replace("{t}", String(nightDoc.next_change))
        : I18n.tr("island.quick.on")
    readonly property string recordValue: recording
        ? I18n.tr("power.quick.record.since").replace("{t}", hhmm(Number(recDoc.since_ms || Date.now())))
        : recDoc.reason === "power.recorder.reason.failed" ? I18n.tr("power.recorder.reason.failed")
        : I18n.tr("power.quick.record.screen")
    readonly property bool saverOffered: (powerDoc.profiles || []).indexOf("power-saver") >= 0

    // Lookups and formats. Pure: no state, so a value is what the document says now.
    function defaultOf(list) {
        if (!list) return null
        for (var i = 0; i < list.length; i++)
            if (list[i]["default"] === true) return list[i]
        return null
    }
    function pad(v) { return (v < 10 ? "0" : "") + v }
    function hhmm(ms) {
        var t = new Date(ms)
        return pad(t.getHours()) + ":" + pad(t.getMinutes())
    }
    function kindLabel(kind) {
        var k = ["wifi", "ethernet", "vpn", "bluetooth"].indexOf(kind) >= 0 ? kind : "other"
        return I18n.tr("island.quick.network.kind." + k)
    }
    function profileLabel(name) {
        var k = "island.quick.power.profile." + name
        var t = I18n.tr(k)
        return t === k ? name : t
    }
    // Whole minutes, at least one: "1 h 20 min", "35 min".
    function duration(s) {
        var m = Math.max(1, Math.round(s / 60))
        if (m >= 60)
            return I18n.tr("island.quick.power.hm").replace("{h}", String(Math.floor(m / 60))).replace("{m}", String(m % 60))
        return I18n.tr("island.quick.power.m").replace("{m}", String(m))
    }
    function timeText() {
        if (powerDoc.time_to_empty_s !== undefined)
            return I18n.tr("island.quick.power.to_empty").replace("{t}", duration(powerDoc.time_to_empty_s))
        if (powerDoc.time_to_full_s !== undefined)
            return I18n.tr("island.quick.power.to_full").replace("{t}", duration(powerDoc.time_to_full_s))
        return ""
    }
    function connectedCount() {
        var n = 0
        var ds = btDoc.devices || []
        for (var i = 0; i < ds.length; i++) if (ds[i].connected === true) n++
        return n
    }

    // The tiles' values in effect (Shōjiki) and the reasons they are inert.
    readonly property string wifiValue: !wifiOn ? I18n.tr("island.quick.off")
        : primary === null ? I18n.tr("island.quick.status.not_connected")
        : primary.kind === "wifi" ? (primaryName !== "" ? primaryName : I18n.tr("island.quick.tile.wifi"))
        : kindLabel(String(primary.kind))
    readonly property string btValue: btDoc.powered !== true ? I18n.tr("island.quick.off")
        : connectedCount() > 0 ? I18n.tr("island.quick.tile.connected_n").replace("{n}", String(connectedCount()))
        : I18n.tr("island.quick.on")
    readonly property string focusValue: !dnd ? I18n.tr("island.quick.off")
        : dndTimed ? I18n.tr("island.quick.tile.until").replace("{t}", hhmm(notesDoc.dnd_until))
        : I18n.tr("island.quick.on")
    readonly property string audioValue: muted ? I18n.tr("island.quick.status.muted") : volPct + " %"
    readonly property string powerValue: battery ? Math.round(Number(powerDoc.percent)) + " %"
        : (String(powerDoc.profile || "") !== "" ? profileLabel(String(powerDoc.profile)) : I18n.tr("island.quick.power.ac"))
    readonly property string displayValue: Math.round(Number(brDoc.percent || 0)) + " %"

    // The status sentence: the whole card in one line, each segment a link to its page.
    function statusList() {
        var out = []
        out.push({text: !netOk ? I18n.tr("island.quick.status.network_unavailable")
            : wifiOn ? wifiValue : I18n.tr("island.quick.status.wifi_off"), page: "wifi"})
        out.push({text: !audioOk ? I18n.tr("island.quick.status.audio_unavailable")
            : muted ? audioValue : (sinkName !== "" ? sinkName + " " : "") + audioValue, page: "audio"})
        var pw = !powerOk ? I18n.tr("island.quick.status.power_unavailable")
            : battery ? Math.round(Number(powerDoc.percent)) + " %" + (timeText() !== "" ? " · " + timeText() : "")
            : powerValue
        out.push({text: pw, page: "power"})
        if (dnd) out.push({text: dndTimed ? I18n.tr("island.quick.status.dnd_until").replace("{t}", hhmm(notesDoc.dnd_until))
            : I18n.tr("island.quick.status.dnd_on"), page: "focus"})
        return out
    }
    readonly property var statusSegments: statusList()

    // The shared requests. Each one holds what the daemon confirms (`value`), sends its action with `start`, and reports a
    // refusal through the translated key it is given (Refusal). Pending shows as "connecting" on every view of the value.
    function cb(report, key) {
        return function (done, err) { if (err) report(refusal.text(err, key)) }
    }
    Refusal { id: refusal }
    Request {
        id: rqWifi
        value: quick.wifiOn
        start: function (to, report) { Store.act("network.wifi", {on: to}, quick.cb(report, "island.quick.network.failed")) }
    }
    Request {
        id: rqAir
        value: quick.netDoc.airplane === true
        start: function (to, report) { Store.act("network.airplane", {on: to}, quick.cb(report, "island.quick.wifi.airplane_failed")) }
    }
    Request {
        id: rqJoin
        value: quick.primary !== null ? quick.primaryName : null
        start: function (to, report) {
            if (to === null) Store.act("network.disconnect", {}, quick.cb(report, "island.quick.wifi.disconnect_failed"))
            else Store.act("network.connect", {ssid: to}, quick.cb(report, "island.quick.wifi.connect_failed"))
        }
    }
    Request {
        id: rqBt
        value: quick.btDoc.powered === true
        start: function (to, report) { Store.act("bluetooth.power", {on: to}, quick.cb(report, "island.quick.bluetooth.failed")) }
    }
    Request {
        id: rqDnd
        value: quick.dnd
        start: function (to, report) { Store.act("notify.dnd", {on: to}, quick.cb(report, "island.quick.focus.failed")) }
    }
    Request {
        id: rqMute
        value: !quick.muted
        start: function (to, report) { Store.act("audio.mute.toggle", {}, quick.cb(report, "island.quick.audio.failed")) }
    }
    Request {
        id: rqMic
        value: !(quick.srcDef !== null && quick.srcDef.muted === true)
        start: function (to, report) { Store.act("audio.mic.mute.toggle", {}, quick.cb(report, "island.quick.audio.mic_failed")) }
    }
    Request {
        id: rqSink
        value: quick.sinkDef !== null ? quick.sinkDef.id : null
        start: function (to, report) { Store.act("audio.sink.default", {id: to}, quick.cb(report, "island.quick.audio.failed")) }
    }
    Request {
        id: rqSrc
        value: quick.srcDef !== null ? quick.srcDef.id : null
        start: function (to, report) { Store.act("audio.source.default", {id: to}, quick.cb(report, "island.quick.audio.source_failed")) }
    }
    Request {
        id: rqProfile
        value: quick.powerDoc.profile !== undefined ? quick.powerDoc.profile : null
        start: function (to, report) { Store.act("power.profile", {name: to}, quick.cb(report, "island.quick.power.failed")) }
    }
    Request {
        id: rqSaver
        value: quick.powerDoc.profile === "power-saver"
        start: function (to, report) {
            Store.act("power.profile", {name: to ? "power-saver" : "balanced"}, quick.cb(report, "island.quick.power.failed"))
        }
    }

    Request {
        id: rqCaffeine
        value: quick.caffeine
        start: function (to, report) { Store.act("idle.caffeine", {on: to}, quick.cb(report, "power.quick.failed")) }
    }
    // K53: light or dark is the user's mode (every palette has both). The theme document says which is in effect; the tile
    // writes the setting, so a style only recommends one until this is used.
    // K55: the scheme in effect (a mode may follow the system or the wallpaper); a press picks dark or light outright.
    readonly property var darkAp: (Store.docs["theme"] || {}).appearance || ({})
    readonly property bool darkOn: String(darkAp.scheme_effective || darkAp.scheme || "") === "dark"
    readonly property string darkSub: darkAp.scheme === "auto" || darkAp.scheme === "wallpaper"
        ? I18n.tr("island.quick.tile.dark." + darkAp.scheme) : I18n.tr(darkOn ? "island.quick.on" : "island.quick.off")
    Request {
        id: rqDark
        value: quick.darkOn
        start: function (to, report) {
            Store.apply([{set: "theme.colors.scheme", value: to ? "dark" : "light"}], function (errors) {
                if (errors && errors.length) report(I18n.tr(String(errors[0].code || "power.quick.failed")))
            })
        }
    }
    Request {
        id: rqNight
        value: quick.nightDoc.enabled === true
        start: function (to, report) { Store.act("nightlight.toggle", {on: to}, quick.cb(report, "power.quick.failed")) }
    }
    Request {
        id: rqRecord
        value: quick.recording
        start: function (to, report) {
            Store.act(to ? "recorder.start" : "recorder.stop", {}, quick.cb(report, "power.quick.record.failed"))
        }
    }

    // Pages: one page at a time, slid in from the right; the tiles slide out to the left.
    // The page the card opens on: the power and bluetooth faces' expanded views (Stage, I44). "" opens on the tiles.
    property string startPage: ""
    property string page: ""           // the page asked for; "" shows the tiles
    property string shownPage: ""      // the page the pane holds; kept while it slides out
    property var returnTo: null        // the control that opened the page: focus goes back there
    property real slide: 0             // 0 the tiles, 1 the page
    readonly property bool tilesShown: page === "" || slide < 1

    function openPage(name, from) {
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
    onPageChanged: {
        if (page !== "") shownPage = page
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
    Component.onCompleted: {
        syncTiles()
        if (startPage !== "") {
            page = startPage
            shownPage = startPage
            slideAnim.stop()    // it opens on the page: no slide in from the tiles
            slide = 1
        }
    }
    // Esc and Left go back from a page (a slider takes Left for itself). On the tiles they pass on, to close the card.
    Keys.onPressed: event => {
        if (quick.page === "") return
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
    readonly property int coreCount: 10
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
        var out = [tWifi, tBt, tFocus, tAudio, tPower, tDisplay, tCaffeine, tNight, tRecord, tDark]
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
            wifiReq: rqWifi
            airReq: rqAir
            joinReq: rqJoin
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: btC
        BluetoothPage { onBackRequested: quick.closePage() }
    }
    Component {
        id: focusC
        FocusPage {
            dndReq: rqDnd
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: audioC
        AudioPage {
            soundReq: rqMute
            sinkReq: rqSink
            micReq: rqMic
            srcReq: rqSrc
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: powerC
        PowerPage {
            profReq: rqProfile
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: displayC
        DisplayPage { onBackRequested: quick.closePage() }
    }
    Component {
        id: nightC
        NightPage {
            nightReq: rqNight
            onBackRequested: quick.closePage()
        }
    }

    // ---- the phone ----
    PhoneFrame {
        id: phone
        visible: !quick.flyout
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
                visible: quick.dnd
                height: phone.statusH
                name: "do_not_disturb_on"
                glyph: "☾"
                filled: true
                size: 15
            },
            Icon {
                visible: quick.netOk
                height: phone.statusH
                name: quick.netGlyph[0]
                glyph: quick.netGlyph[1]
                filled: true
                size: 15
            },
            Icon {
                visible: quick.battery
                height: phone.statusH
                name: quick.batteryIcon
                glyph: "▮"
                filled: true
                size: 15
            },
            Text {
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                antialiasing: !Theme.pixelType
                font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                visible: quick.battery
                height: phone.statusH
                verticalAlignment: Text.AlignVCenter
                color: Theme.fg
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: quick.battery ? Math.round(Number(quick.powerDoc.percent)) + "%" : ""
            }
        ]

        // The screen's content: the tiles and the page side by side, sliding inside the screen.
        Item {
            id: viewport
            // (the flyout's area under `quick.frame = flyout`; the phone's screen otherwise)
            parent: quick.flyout ? flyArea : phone.area
            width: parent.width
            height: parent.height
            clip: true

            Column {
                id: tilesPane
                width: quick.innerW
                spacing: Theme.gap
                x: Theme.pad - quick.slide * viewport.width
                visible: quick.tilesShown

                // The greeting row (SekaiPop's user row): an avatar key, the time of day's greeting and the card's name.
                Item {
                    id: hello
                    // (a flyout has no greeting row, as 11's has none)
                    visible: !quick.flyout
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
                    Keys.onPressed: event => {
                        var cells = quick.tileCells()
                        var i = -1
                        for (var k = 0; k < cells.length; k++) if (cells[k] !== null && cells[k].activeFocus) i = k
                        if (i < 0) return
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

                    QuickTile {
                        id: tWifi
                        width: quick.tileW
                        glyph: "≋"
                        icon: quick.wifiOn ? "wifi" : "wifi_off"
                        label: I18n.tr("island.quick.tile.wifi")
                        subtitle: quick.wifiValue
                        reason: quick.netOk ? "" : I18n.tr("island.quick.tile.no_network")
                        forcedBy: String(quick.netDoc.forced_by || "")
                        on: quick.wifiOn
                        req: rqWifi
                        pendingText: I18n.tr("island.quick.connecting")
                        onPageRequested: quick.openPage("wifi", tWifi)
                    }
                    QuickTile {
                        id: tBt
                        width: quick.tileW
                        glyph: "ᛒ"
                        icon: quick.btDoc.powered === true ? "bluetooth" : "bluetooth_disabled"
                        label: I18n.tr("island.quick.tile.bluetooth")
                        subtitle: quick.btValue
                        reason: quick.btOk ? "" : I18n.tr("island.quick.tile.no_bluetooth")
                        forcedBy: String(quick.btDoc.forced_by || "")
                        on: quick.btDoc.powered === true
                        req: rqBt
                        pendingText: I18n.tr("island.quick.connecting")
                        onPageRequested: quick.openPage("bluetooth", tBt)
                    }
                    QuickTile {
                        id: tFocus
                        width: quick.tileW
                        glyph: "☾"
                        icon: "bedtime"
                        label: I18n.tr("island.quick.tile.focus")
                        subtitle: quick.focusValue
                        reason: quick.notifyOk ? "" : I18n.tr("island.quick.tile.no_notify")
                        forcedBy: String(quick.notesDoc.forced_by || "")
                        on: quick.dnd
                        req: rqDnd
                        pendingText: I18n.tr("island.quick.changing")
                        onPageRequested: quick.openPage("focus", tFocus)
                    }
                    QuickTile {
                        id: tAudio
                        width: quick.tileW
                        glyph: "♪"
                        icon: quick.muted ? "volume_off" : "volume_up"
                        label: I18n.tr("island.quick.tile.audio")
                        subtitle: quick.audioValue
                        reason: quick.audioOk ? "" : I18n.tr("island.quick.tile.no_audio")
                        forcedBy: String(quick.audioDoc.forced_by || "")
                        on: !quick.muted
                        req: rqMute
                        pendingText: I18n.tr("island.quick.changing")
                        onPageRequested: quick.openPage("audio", tAudio)
                    }
                    QuickTile {
                        id: tPower
                        width: quick.tileW
                        glyph: "⚡"
                        icon: quick.powerDoc.profile === "power-saver" ? "energy_savings_leaf" : "bolt"
                        label: I18n.tr("island.quick.tile.power")
                        subtitle: quick.powerValue
                        reason: quick.powerOk ? "" : I18n.tr("island.quick.tile.no_power")
                        forcedBy: String(quick.powerDoc.forced_by || "")
                        on: quick.powerDoc.profile === "power-saver"
                        toggles: quick.saverOffered
                        req: rqSaver
                        pendingText: I18n.tr("island.quick.changing")
                        onPageRequested: quick.openPage("power", tPower)
                    }
                    QuickTile {
                        id: tDisplay
                        width: quick.tileW
                        glyph: "☼"
                        icon: "light_mode"
                        label: I18n.tr("island.quick.tile.display")
                        subtitle: quick.brOk ? quick.displayValue : ""
                        reason: quick.brOk ? "" : I18n.tr("island.quick.tile.no_backlight")
                        forcedBy: String(quick.brDoc.forced_by || "")
                        toggles: false
                        onPageRequested: quick.openPage("display", tDisplay)
                    }
                    // K47 (W23-system, docs/ux/power.md): keep awake, night light, record. A missing program, protocol or
                    // compositor is the tile's reason, never a dead tile.
                    QuickTile {
                        id: tCaffeine
                        width: quick.tileW
                        glyph: "☕"
                        icon: "coffee"
                        label: I18n.tr("power.quick.caffeine")
                        subtitle: quick.caffeineValue
                        reason: !quick.idleOk ? I18n.tr("power.quick.caffeine.no_idle")
                            : quick.idleDoc.reason ? I18n.tr(String(quick.idleDoc.reason)) : ""
                        on: quick.caffeine
                        req: rqCaffeine
                        hasPage: false
                        onSecondaryRequested: quick.openSettings("power")
                        pendingText: I18n.tr("island.quick.changing")
                    }
                    QuickTile {
                        id: tNight
                        width: quick.tileW
                        glyph: "◐"
                        icon: "nightlight"
                        label: I18n.tr("power.night.title")
                        subtitle: quick.nightValue
                        reason: !quick.nightOk ? I18n.tr("power.quick.night.none")
                            : quick.nightDoc.available === false && quick.nightDoc.reason ? I18n.tr(String(quick.nightDoc.reason)) : ""
                        on: quick.nightDoc.enabled === true
                        req: rqNight
                        pendingText: I18n.tr("island.quick.changing")
                        onPageRequested: quick.openPage("night", tNight)
                    }
                    QuickTile {
                        id: tRecord
                        width: quick.tileW
                        glyph: "●"
                        icon: quick.recording ? "stop_circle" : "screen_record"
                        label: I18n.tr("power.quick.record")
                        subtitle: quick.recordValue
                        reason: !quick.recOk ? I18n.tr("power.quick.record.none")
                            : quick.recDoc.available === false && !quick.recording && quick.recDoc.reason === "power.recorder.reason.missing"
                                ? I18n.tr("power.recorder.reason.missing") : ""
                        on: quick.recording
                        req: rqRecord
                        hasPage: false
                        onSecondaryRequested: quick.openSettings("power")
                        pendingText: I18n.tr("power.quick.record.starting")
                    }
                    QuickTile {
                        id: tDark
                        width: quick.tileW
                        glyph: "☾"
                        icon: "dark_mode"
                        label: I18n.tr("island.quick.tile.dark")
                        subtitle: quick.darkSub
                        on: quick.darkOn
                        req: rqDark
                        hasPage: false
                        onSecondaryRequested: quick.openSettings("appearance")
                        pendingText: I18n.tr("island.quick.changing")
                    }
                    // K28 `quick.tiles` (W18): one cell per ready contribution, after the core tiles, in the same 2-column flow. A
                    // cell is a tile's size (SlotHost's cell: half the card less the gap, 56 px) and clips what is not a tile.
                    Repeater {
                        id: modCells
                        model: quick.tileList
                        delegate: tileSlot.cell
                    }
                }

                LevelRow {
                    width: quick.innerW
                    glyph: "♪"
                    icon: quick.muted ? "volume_off" : "volume_up"
                    value: quick.audioOk ? Math.max(0, Math.min(1, Number(quick.audioDoc.volume || 0))) : 0
                    readout: quick.audioOk ? (quick.muted ? I18n.tr("island.quick.status.muted") : quick.volPct + " %") : ""
                    unavailable: !quick.audioOk
                    a11y: I18n.tr("island.quick.level.volume")
                    onMoved: v => Store.intent("audio.volume", v, quick.intentOrigin)
                }
                // The output device under its level: a link to the Audio page (a Tab stop, Enter opens it).
                Item {
                    id: chip
                    width: quick.innerW
                    height: visible ? 24 : 0
                    visible: quick.audioOk && quick.sinkName !== ""
                    activeFocusOnTab: true
                    Keys.onReturnPressed: quick.openPage("audio", chip)
                    Keys.onEnterPressed: quick.openPage("audio", chip)
                    Keys.onSpacePressed: quick.openPage("audio", chip)
                    Accessible.role: Accessible.Button
                    Accessible.name: quick.sinkName

                    Rectangle {
                        id: pill
                        x: 20 + Theme.gap
                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        width: Math.min(pillText.implicitWidth + 2 * Theme.gap, chip.width - x)
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.outline
                        Text {
                            id: pillText
                            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                            antialiasing: !Theme.pixelType
                            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                            x: Theme.gap
                            width: pill.width - 2 * Theme.gap
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.pixelSize: Theme.fsCaption
                            font.family: Theme.fam(text, Theme.families)
                            text: quick.sinkName
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: quick.openPage("audio", chip)
                    }
                    FocusRing {
                        anchors.fill: pill
                        shown: chip.activeFocus
                        corner: pill.radius
                    }
                }
                // The rows that are not always there are made only while they show (W37, I199): a card with no backlight
                // and nothing playing builds neither. A Loader that is not visible takes no space and no spacing.
                Loader {
                    width: quick.innerW
                    visible: quick.brOk
                    active: quick.brOk
                    sourceComponent: Component {
                        LevelRow {
                            width: quick.innerW
                            glyph: "☼"
                            icon: "light_mode"
                            value: quick.brLevel
                            readout: quick.brOk ? quick.displayValue : ""
                            a11y: I18n.tr("island.brightness.heading")
                            onMoved: v => Store.intent("brightness.set", v, quick.intentOrigin)
                        }
                    }
                }
                Loader {
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
                QuickFooter {
                    visible: !quick.flyout
                    width: quick.innerW
                    sessionOk: quick.sessionOk
                }
            }

            Loader {
                id: pageLoader
                width: quick.innerW
                x: Theme.pad + (1 - quick.slide) * viewport.width
                active: quick.shownPage !== ""
                sourceComponent: quick.shownPage === "wifi" ? wifiC
                    : quick.shownPage === "bluetooth" ? btC
                    : quick.shownPage === "focus" ? focusC
                    : quick.shownPage === "audio" ? audioC
                    : quick.shownPage === "power" ? powerC
                    : quick.shownPage === "display" ? displayC
                    : quick.shownPage === "night" ? nightC : null
                // The page's first control takes the focus once it exists (after the Loader has made it).
                onStatusChanged: if (status === Loader.Ready && item !== null)
                    Qt.callLater(function () { if (pageLoader.item !== null) pageLoader.item.focusFirst() })
            }
        }
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
                        visible: quick.battery
                        Icon { name: quick.batteryIcon; glyph: "▮"; size: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.fg
                            font.pixelSize: Theme.fsLabel
                            font.family: Theme.fam(text, Theme.families)
                            text: quick.battery ? Math.round(Number(quick.powerDoc.percent)) + " %" : ""
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
