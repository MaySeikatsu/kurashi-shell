import QtQuick
import "../core"
import "expanded"
import "quick"

// The quick settings card (K24, W13; docs/ux/quick-settings.md): the `quick` panel of runtime.ui, opened by the bar's button or
// `quick.toggle`. The tiles are the view: a status sentence, six tiles (Wi-Fi, Bluetooth, Focus, Audio, Power, Display), the
// mod tiles of `quick.tiles`, the output and brightness levels, the media row while something plays, and the session footer.
// A tile's arrow, a status segment, or Right opens its page in the same card: the content slides, Esc or ← goes back, and Esc
// on the tiles closes the card (through the Stage). Every document the card shows is watched while it is up (Ma); a page
// watches what it lists only while it is on screen. Requests are owned here, so a tile and its page show one state.
Item {
    id: quick
    width: parent.width
    height: quick.shownPage !== "" ? pageLoader.height : tilesPane.height
    clip: true

    // Documents: the card's own (the tiles, the status, the levels) are watched while it is up.
    Watch { doc: "svc.network" }
    Watch { doc: "svc.audio" }
    Watch { doc: "svc.power" }
    Watch { doc: "svc.bluetooth" }
    Watch { doc: "svc.brightness" }
    Watch { doc: "svc.notifications" }
    Watch { doc: "svc.media" }
    Watch { doc: "svc.session" }

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
        duration: Theme.emphMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.enterCurve
        onFinished: if (quick.page === "") quick.shownPage = ""
    }
    Component.onCompleted: if (startPage !== "") {
        page = startPage
        shownPage = startPage
        slideAnim.stop()    // it opens on the page: no slide in from the tiles
        slide = 1
    }
    // Esc and Left go back from a page (a slider takes Left for itself). On the tiles they pass on, to close the card.
    Keys.onPressed: event => {
        if (quick.page === "") return
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Left) {
            quick.closePage()
            event.accepted = true
        }
    }

    Column {
        id: tilesPane
        width: quick.width
        spacing: Theme.gap
        x: -quick.slide * quick.width
        visible: quick.tilesShown

        Text {
            width: quick.width
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.quick.heading")
        }
        QuickStatus {
            id: statusLine
            width: quick.width
            segments: quick.statusSegments
            onOpened: (target, from) => quick.openPage(target, from)
        }
        Grid {
            id: grid
            width: quick.width
            columns: 2
            spacing: Theme.gap
            readonly property var cells: [tWifi, tBt, tFocus, tAudio, tPower, tDisplay]
            // Up and Down move within a column, Left and Right between the two columns; Right on a tile opens its page.
            Keys.onPressed: event => {
                var i = -1
                for (var k = 0; k < grid.cells.length; k++) if (grid.cells[k].activeFocus) i = k
                if (i < 0) return
                var to = -1
                switch (event.key) {
                case Qt.Key_Up: to = i >= 2 ? i - 2 : -1; break
                case Qt.Key_Down: to = i + 2 < grid.cells.length ? i + 2 : -1; break
                case Qt.Key_Left: to = i % 2 === 1 ? i - 1 : -1; break
                case Qt.Key_Right: to = i % 2 === 0 ? i + 1 : -1; break
                default: return
                }
                if (to >= 0) grid.cells[to].forceActiveFocus()
                event.accepted = true
            }

            QuickTile {
                id: tWifi
                width: (grid.width - grid.spacing) / 2
                glyph: "≋"
                label: I18n.tr("island.quick.tile.wifi")
                subtitle: quick.wifiValue
                reason: quick.netOk ? "" : I18n.tr("island.quick.tile.no_network")
                on: quick.wifiOn
                req: rqWifi
                pendingText: I18n.tr("island.quick.connecting")
                onPageRequested: quick.openPage("wifi", tWifi)
            }
            QuickTile {
                id: tBt
                width: (grid.width - grid.spacing) / 2
                glyph: "ᛒ"
                label: I18n.tr("island.quick.tile.bluetooth")
                subtitle: quick.btValue
                reason: quick.btOk ? "" : I18n.tr("island.quick.tile.no_bluetooth")
                on: quick.btDoc.powered === true
                req: rqBt
                pendingText: I18n.tr("island.quick.connecting")
                onPageRequested: quick.openPage("bluetooth", tBt)
            }
            QuickTile {
                id: tFocus
                width: (grid.width - grid.spacing) / 2
                glyph: "☾"
                label: I18n.tr("island.quick.tile.focus")
                subtitle: quick.focusValue
                reason: quick.notifyOk ? "" : I18n.tr("island.quick.tile.no_notify")
                on: quick.dnd
                req: rqDnd
                pendingText: I18n.tr("island.quick.changing")
                onPageRequested: quick.openPage("focus", tFocus)
            }
            QuickTile {
                id: tAudio
                width: (grid.width - grid.spacing) / 2
                glyph: "♪"
                label: I18n.tr("island.quick.tile.audio")
                subtitle: quick.audioValue
                reason: quick.audioOk ? "" : I18n.tr("island.quick.tile.no_audio")
                on: !quick.muted
                req: rqMute
                pendingText: I18n.tr("island.quick.changing")
                onPageRequested: quick.openPage("audio", tAudio)
            }
            QuickTile {
                id: tPower
                width: (grid.width - grid.spacing) / 2
                glyph: "⚡"
                label: I18n.tr("island.quick.tile.power")
                subtitle: quick.powerValue
                reason: quick.powerOk ? "" : I18n.tr("island.quick.tile.no_power")
                on: quick.powerDoc.profile === "power-saver"
                toggles: quick.saverOffered
                req: rqSaver
                pendingText: I18n.tr("island.quick.changing")
                onPageRequested: quick.openPage("power", tPower)
            }
            QuickTile {
                id: tDisplay
                width: (grid.width - grid.spacing) / 2
                glyph: "☼"
                label: I18n.tr("island.quick.tile.display")
                subtitle: quick.brOk ? quick.displayValue : ""
                reason: quick.brOk ? "" : I18n.tr("island.quick.tile.no_backlight")
                toggles: false
                onPageRequested: quick.openPage("display", tDisplay)
            }
        }
        // K28: mod tiles (caffeine, wallpaper next, VPN) wrap below the tiles; none takes no space.
        SlotHost { slot: "quick.tiles"; layout: "flow"; width: quick.width }

        LevelRow {
            width: quick.width
            glyph: "♪"
            value: quick.audioOk ? Math.max(0, Math.min(1, Number(quick.audioDoc.volume || 0))) : 0
            readout: quick.audioOk ? (quick.muted ? I18n.tr("island.quick.status.muted") : quick.volPct + " %") : ""
            unavailable: !quick.audioOk
            a11y: I18n.tr("island.quick.level.volume")
            onMoved: v => Store.intent("audio.volume", v, quick.intentOrigin)
        }
        // The output device under its level: a link to the Audio page (a Tab stop, Enter opens it).
        Item {
            id: chip
            width: quick.width
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
        LevelRow {
            visible: quick.brOk
            width: quick.width
            glyph: "☼"
            value: quick.brLevel
            readout: quick.brOk ? quick.displayValue : ""
            a11y: I18n.tr("island.brightness.heading")
            onMoved: v => Store.intent("brightness.set", v, quick.intentOrigin)
        }
        QuickMedia {
            width: quick.width
            visible: quick.mediaPlaying
            d: quick.mediaDoc
            // The island's media view: its expanded card, with the transport in it.
            onOpenRequested: Store.act("island.expand")
        }
        QuickFooter {
            width: quick.width
            sessionOk: quick.sessionOk
        }
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
    Loader {
        id: pageLoader
        width: quick.width
        x: (1 - quick.slide) * quick.width
        active: quick.shownPage !== ""
        sourceComponent: quick.shownPage === "wifi" ? wifiC
            : quick.shownPage === "bluetooth" ? btC
            : quick.shownPage === "focus" ? focusC
            : quick.shownPage === "audio" ? audioC
            : quick.shownPage === "power" ? powerC
            : quick.shownPage === "display" ? displayC : null
        // The page's first control takes the focus once it exists (after the Loader has made it).
        onStatusChanged: if (status === Loader.Ready && item !== null)
            Qt.callLater(function () { if (pageLoader.item !== null) pageLoader.item.focusFirst() })
    }
}
