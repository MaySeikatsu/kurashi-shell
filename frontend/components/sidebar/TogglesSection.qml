import QtQuick
import "../../core"
import ".."
import "../quick"
import "../expanded"

// The right sidebar's `toggles` (docs/ux/sidebar.md): the quick tiles (QuickTile, Request — the quick card's components,
// docs/ux/quick-settings.md) two by two — Wi-Fi, Bluetooth, Focus, Audio, Power saver, Keep awake, Night light, Record —
// then the `quick.tiles` mod tiles (K28). A tile's arrow asks for its quick-settings page (`pageRequested`); the column
// shows it over the sections, ← / Esc back. The values are the daemon's, each request pending until it confirms
// (Shōjiki). The tile values repeat QuickPanel's for the tiles shown here (follow-up: one shared quick state, BACKLOG).
// Watches its documents only while the sidebar is open (it exists only then, Ma).
Item {
    id: tg
    implicitHeight: grid.height
    signal pageRequested(Component page, Item from)

    Watch { doc: "svc.network" }
    Watch { doc: "svc.audio" }
    Watch { doc: "svc.power" }
    Watch { doc: "svc.bluetooth" }
    Watch { doc: "svc.notifications" }
    Watch { doc: "svc.idle" }
    Watch { doc: "svc.nightlight" }
    Watch { doc: "svc.recorder" }

    readonly property var netDoc: Store.docs["svc.network"] || ({})
    readonly property bool netOk: typeof netDoc.state === "string" && netDoc.state !== "unavailable"
    readonly property bool wifiOn: netDoc.wifi_enabled === true
    readonly property var primary: netDoc.primary || null
    readonly property var btDoc: Store.docs["svc.bluetooth"] || ({})
    readonly property var audioDoc: Store.docs["svc.audio"] || ({})
    readonly property bool audioOk: audioDoc.available === true
    readonly property bool muted: audioDoc.muted === true
    readonly property var powerDoc: Store.docs["svc.power"] || ({})
    readonly property bool battery: powerDoc.present === true && powerDoc.percent !== undefined
    readonly property var notesDoc: Store.docs["svc.notifications"] || ({})
    readonly property bool dnd: notesDoc.dnd === true
    readonly property var idleDoc: Store.docs["svc.idle"] || ({})
    readonly property bool caffeine: idleDoc.caffeine === true
    readonly property var nightDoc: Store.docs["svc.nightlight"] || ({})
    readonly property var recDoc: Store.docs["svc.recorder"] || ({})
    readonly property bool recording: recDoc.recording === true
    readonly property var sinkDef: defaultOf(audioOk ? audioDoc.sinks : null)
    readonly property var srcDef: audioOk && audioDoc.source ? audioDoc.source : null

    function defaultOf(list) {
        if (!list) return null
        for (var i = 0; i < list.length; i++) if (list[i]["default"] === true) return list[i]
        return null
    }
    function pad(v) { return (v < 10 ? "0" : "") + v }
    function hhmm(ms) { var t = new Date(ms); return pad(t.getHours()) + ":" + pad(t.getMinutes()) }
    function connectedCount() {
        var n = 0, ds = btDoc.devices || []
        for (var i = 0; i < ds.length; i++) if (ds[i].connected === true) n++
        return n
    }
    function cb(report, key) { return function (done, err) { if (err) report(refusal.text(err, key)) } }
    Refusal { id: refusal }

    // ---- the requests (the quick card's, one per switch) ----
    Request { id: rqWifi; value: tg.wifiOn
        start: function (to, report) { Store.act("network.wifi", {on: to}, tg.cb(report, "island.quick.network.failed")) } }
    Request { id: rqAir; value: tg.netDoc.airplane === true
        start: function (to, report) { Store.act("network.airplane", {on: to}, tg.cb(report, "island.quick.wifi.airplane_failed")) } }
    Request { id: rqJoin; value: tg.primary !== null ? String(tg.primary.name || "") : null
        start: function (to, report) {
            if (to === null) Store.act("network.disconnect", {}, tg.cb(report, "island.quick.wifi.disconnect_failed"))
            else Store.act("network.connect", {ssid: to}, tg.cb(report, "island.quick.wifi.connect_failed"))
        } }
    Request { id: rqBt; value: tg.btDoc.powered === true
        start: function (to, report) { Store.act("bluetooth.power", {on: to}, tg.cb(report, "island.quick.bluetooth.failed")) } }
    Request { id: rqDnd; value: tg.dnd
        start: function (to, report) { Store.act("notify.dnd", {on: to}, tg.cb(report, "island.quick.focus.failed")) } }
    Request { id: rqMute; value: !tg.muted
        start: function (to, report) { Store.act("audio.mute.toggle", {}, tg.cb(report, "island.quick.audio.failed")) } }
    Request { id: rqMic; value: !(tg.srcDef !== null && tg.srcDef.muted === true)
        start: function (to, report) { Store.act("audio.mic.mute.toggle", {}, tg.cb(report, "island.quick.audio.mic_failed")) } }
    Request { id: rqSink; value: tg.sinkDef !== null ? tg.sinkDef.id : null
        start: function (to, report) { Store.act("audio.sink.default", {id: to}, tg.cb(report, "island.quick.audio.failed")) } }
    Request { id: rqSrc; value: tg.srcDef !== null ? tg.srcDef.id : null
        start: function (to, report) { Store.act("audio.source.default", {id: to}, tg.cb(report, "island.quick.audio.source_failed")) } }
    Request { id: rqProfile; value: tg.powerDoc.profile !== undefined ? tg.powerDoc.profile : null
        start: function (to, report) { Store.act("power.profile", {name: to}, tg.cb(report, "island.quick.power.failed")) } }
    Request { id: rqSaver; value: tg.powerDoc.profile === "power-saver"
        start: function (to, report) {
            Store.act("power.profile", {name: to ? "power-saver" : "balanced"}, tg.cb(report, "island.quick.power.failed"))
        } }
    Request { id: rqCaffeine; value: tg.caffeine
        start: function (to, report) { Store.act("idle.caffeine", {on: to}, tg.cb(report, "power.quick.failed")) } }
    Request { id: rqNight; value: tg.nightDoc.enabled === true
        start: function (to, report) { Store.act("nightlight.toggle", {on: to}, tg.cb(report, "power.quick.failed")) } }
    Request { id: rqRecord; value: tg.recording
        start: function (to, report) {
            Store.act(to ? "recorder.start" : "recorder.stop", {}, tg.cb(report, "power.quick.record.failed"))
        } }

    // K53: light or dark, the user's mode (as the quick card's Dark mode tile).
    readonly property bool darkOn: String((Store.docs["theme"] || {}).appearance ? Store.docs["theme"].appearance.scheme : "") === "dark"
    Request { id: rqDark; value: tg.darkOn
        start: function (to, report) {
            Store.apply([{set: "theme.colors.scheme", value: to ? "dark" : "light"}], function (errors) {
                if (errors && errors.length) report(I18n.tr(String(errors[0].code || "power.quick.failed")))
            })
        } }

    // ---- the pages (the quick card's), made by the column over the sections ----
    Component { id: wifiC; WifiPage { live: true; wifiReq: rqWifi; airReq: rqAir; joinReq: rqJoin } }
    Component { id: btC; BluetoothPage {} }
    Component { id: focusC; FocusPage { dndReq: rqDnd } }
    Component { id: audioC; AudioPage { soundReq: rqMute; sinkReq: rqSink; micReq: rqMic; srcReq: rqSrc } }
    Component { id: powerC; PowerPage { profReq: rqProfile } }
    Component { id: nightC; NightPage { nightReq: rqNight } }
    // The microphone switch of the sliders section shares this request.
    readonly property var micReq: rqMic
    readonly property var sinkReq: rqSink

    readonly property real cellW: (width - Theme.gap) / 2
    SlotHost {
        id: tileSlot
        slot: "quick.tiles"
        layout: "cells"
        cellWidth: tg.cellW
        cellHeight: 56
    }
    function cells() {
        var out = [tWifi, tBt, tFocus, tAudio, tPower, tCaffeine, tNight, tRecord, tDark]
        for (var i = 0; i < modCells.count; i++) {
            var c = modCells.itemAt(i), t = c !== null ? c.tile : null
            out.push(t !== null && t !== undefined && t.isTile === true ? t : null)
        }
        return out
    }

    Grid {
        id: grid
        width: tg.width
        columns: 2
        spacing: Theme.gap
        // As the quick card: Up and Down within a column, Left and Right between the columns.
        Keys.onPressed: event => {
            var cs = tg.cells(), i = -1
            for (var k = 0; k < cs.length; k++) if (cs[k] !== null && cs[k].activeFocus) i = k
            if (i < 0) return
            var to = -1
            switch (event.key) {
            case Qt.Key_Up: to = i >= 2 ? i - 2 : -1; break
            case Qt.Key_Down: to = i + 2 < cs.length ? i + 2 : -1; break
            case Qt.Key_Left: to = i % 2 === 1 ? i - 1 : -1; break
            case Qt.Key_Right: to = i % 2 === 0 ? i + 1 : -1; break
            default: return
            }
            if (to >= 0 && cs[to] !== null) cs[to].forceActiveFocus()
            event.accepted = true
        }
        QuickTile {
            id: tWifi
            width: tg.cellW
            glyph: "≋"
            icon: tg.wifiOn ? "wifi" : "wifi_off"
            label: I18n.tr("island.quick.tile.wifi")
            subtitle: !tg.wifiOn ? I18n.tr("island.quick.off")
                : tg.primary === null ? I18n.tr("island.quick.status.not_connected")
                : String(tg.primary.name || I18n.tr("island.quick.tile.wifi"))
            reason: tg.netOk ? "" : I18n.tr("island.quick.tile.no_network")
            forcedBy: String(tg.netDoc.forced_by || "")
            on: tg.wifiOn
            req: rqWifi
            pendingText: I18n.tr("island.quick.connecting")
            onPageRequested: tg.pageRequested(wifiC, tWifi)
        }
        QuickTile {
            id: tBt
            width: tg.cellW
            glyph: "ᛒ"
            icon: tg.btDoc.powered === true ? "bluetooth" : "bluetooth_disabled"
            label: I18n.tr("island.quick.tile.bluetooth")
            subtitle: tg.btDoc.powered !== true ? I18n.tr("island.quick.off")
                : tg.connectedCount() > 0 ? I18n.tr("island.quick.tile.connected_n").replace("{n}", String(tg.connectedCount()))
                : I18n.tr("island.quick.on")
            reason: tg.btDoc.available === true ? "" : I18n.tr("island.quick.tile.no_bluetooth")
            forcedBy: String(tg.btDoc.forced_by || "")
            on: tg.btDoc.powered === true
            req: rqBt
            pendingText: I18n.tr("island.quick.connecting")
            onPageRequested: tg.pageRequested(btC, tBt)
        }
        QuickTile {
            id: tFocus
            width: tg.cellW
            glyph: "☾"
            icon: "bedtime"
            label: I18n.tr("island.quick.tile.focus")
            subtitle: !tg.dnd ? I18n.tr("island.quick.off")
                : typeof tg.notesDoc.dnd_until === "number"
                    ? I18n.tr("island.quick.tile.until").replace("{t}", tg.hhmm(tg.notesDoc.dnd_until))
                : I18n.tr("island.quick.on")
            reason: Store.docs["svc.notifications"] !== undefined ? "" : I18n.tr("island.quick.tile.no_notify")
            forcedBy: String(tg.notesDoc.forced_by || "")
            on: tg.dnd
            req: rqDnd
            pendingText: I18n.tr("island.quick.changing")
            onPageRequested: tg.pageRequested(focusC, tFocus)
        }
        QuickTile {
            id: tAudio
            width: tg.cellW
            glyph: "♪"
            icon: tg.muted ? "volume_off" : "volume_up"
            label: I18n.tr("island.quick.tile.audio")
            subtitle: tg.muted ? I18n.tr("island.quick.status.muted") : Math.round(Number(tg.audioDoc.volume || 0) * 100) + " %"
            reason: tg.audioOk ? "" : I18n.tr("island.quick.tile.no_audio")
            forcedBy: String(tg.audioDoc.forced_by || "")
            on: !tg.muted
            req: rqMute
            pendingText: I18n.tr("island.quick.changing")
            onPageRequested: tg.pageRequested(audioC, tAudio)
        }
        QuickTile {
            id: tPower
            width: tg.cellW
            glyph: "⚡"
            icon: tg.powerDoc.profile === "power-saver" ? "energy_savings_leaf" : "bolt"
            label: I18n.tr("island.quick.tile.power")
            subtitle: tg.battery ? Math.round(Number(tg.powerDoc.percent)) + " %" : I18n.tr("island.quick.power.ac")
            reason: tg.powerDoc.available === true ? "" : I18n.tr("island.quick.tile.no_power")
            forcedBy: String(tg.powerDoc.forced_by || "")
            on: tg.powerDoc.profile === "power-saver"
            toggles: (tg.powerDoc.profiles || []).indexOf("power-saver") >= 0
            req: rqSaver
            pendingText: I18n.tr("island.quick.changing")
            onPageRequested: tg.pageRequested(powerC, tPower)
        }
        QuickTile {
            id: tCaffeine
            width: tg.cellW
            glyph: "☕"
            icon: "coffee"
            label: I18n.tr("power.quick.caffeine")
            subtitle: tg.caffeine ? I18n.tr("power.quick.caffeine.on")
                : tg.idleDoc.enabled === false ? I18n.tr("power.quick.caffeine.idle_off") : I18n.tr("island.quick.off")
            reason: Store.docs["svc.idle"] === undefined ? I18n.tr("power.quick.caffeine.no_idle")
                : tg.idleDoc.reason ? I18n.tr(String(tg.idleDoc.reason)) : ""
            on: tg.caffeine
            req: rqCaffeine
            hasPage: false
            pendingText: I18n.tr("island.quick.changing")
        }
        QuickTile {
            id: tNight
            width: tg.cellW
            glyph: "◐"
            icon: "nightlight"
            label: I18n.tr("power.night.title")
            subtitle: tg.nightDoc.enabled === true ? I18n.tr("island.quick.on") : I18n.tr("island.quick.off")
            reason: Store.docs["svc.nightlight"] === undefined ? I18n.tr("power.quick.night.none")
                : tg.nightDoc.available === false && tg.nightDoc.reason ? I18n.tr(String(tg.nightDoc.reason)) : ""
            on: tg.nightDoc.enabled === true
            req: rqNight
            pendingText: I18n.tr("island.quick.changing")
            onPageRequested: tg.pageRequested(nightC, tNight)
        }
        QuickTile {
            id: tRecord
            width: tg.cellW
            glyph: "●"
            icon: tg.recording ? "stop_circle" : "screen_record"
            label: I18n.tr("power.quick.record")
            subtitle: tg.recording ? I18n.tr("power.quick.record.since").replace("{t}", tg.hhmm(Number(tg.recDoc.since_ms || Date.now())))
                : I18n.tr("power.quick.record.screen")
            reason: Store.docs["svc.recorder"] === undefined ? I18n.tr("power.quick.record.none")
                : tg.recDoc.available === false && !tg.recording && tg.recDoc.reason === "power.recorder.reason.missing"
                    ? I18n.tr("power.recorder.reason.missing") : ""
            on: tg.recording
            req: rqRecord
            hasPage: false
            pendingText: I18n.tr("power.quick.record.starting")
        }
        QuickTile {
            id: tDark
            width: tg.cellW
            glyph: "☾"
            icon: "dark_mode"
            label: I18n.tr("island.quick.tile.dark")
            subtitle: tg.darkOn ? I18n.tr("island.quick.on") : I18n.tr("island.quick.off")
            on: tg.darkOn
            req: rqDark
            hasPage: false
            pendingText: I18n.tr("island.quick.changing")
        }
        Repeater {
            id: modCells
            model: tileSlot.entries
            delegate: tileSlot.cell
        }
    }
}
