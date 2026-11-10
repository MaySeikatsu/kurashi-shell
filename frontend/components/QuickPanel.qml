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
            wifiReq: cWifi.req
            airReq: cAir.req
            joinReq: cWifi.joinReq
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
            dndReq: cFocus.req
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
            onBackRequested: quick.closePage()
        }
    }
    Component {
        id: powerC
        PowerPage {
            profReq: cPower.profileReq
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
            nightReq: cNight.req
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

                    // W70: each tile is drawn from its control (quick/*Control.qml); the page it opens is the control's.
                    ControlTile { id: tWifi; width: quick.tileW; ctl: cWifi; onPageRequested: quick.openPage(ctl.page, tWifi) }
                    ControlTile { id: tBt; width: quick.tileW; ctl: cBt; onPageRequested: quick.openPage(ctl.page, tBt) }
                    ControlTile { id: tFocus; width: quick.tileW; ctl: cFocus; onPageRequested: quick.openPage(ctl.page, tFocus) }
                    ControlTile { id: tAudio; width: quick.tileW; ctl: cAudio; onPageRequested: quick.openPage(ctl.page, tAudio) }
                    ControlTile { id: tPower; width: quick.tileW; ctl: cPower; onPageRequested: quick.openPage(ctl.page, tPower) }
                    ControlTile { id: tDisplay; width: quick.tileW; ctl: cBright; onPageRequested: quick.openPage(ctl.page, tDisplay) }
                    // K47 (W23-system, docs/ux/power.md): keep awake, night light, record. A missing program, protocol or
                    // compositor is the tile's reason, never a dead tile. A tile without a page opens its Settings page.
                    ControlTile { id: tCaffeine; width: quick.tileW; ctl: cCaffeine; onSecondaryRequested: quick.openSettings(ctl.settingsPage) }
                    ControlTile { id: tNight; width: quick.tileW; ctl: cNight; onPageRequested: quick.openPage(ctl.page, tNight) }
                    ControlTile { id: tRecord; width: quick.tileW; ctl: cRecord; onSecondaryRequested: quick.openSettings(ctl.settingsPage) }
                    ControlTile { id: tDark; width: quick.tileW; ctl: cDark; onSecondaryRequested: quick.openSettings(ctl.settingsPage) }
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
                    icon: cAudio.icon
                    value: cAudio.level
                    readout: cAudio.ok ? cAudio.value : ""
                    unavailable: !cAudio.ok
                    a11y: I18n.tr("island.quick.level.volume")
                    onMoved: v => Store.intent("audio.volume", v, quick.intentOrigin)
                }
                // The output device under its level: a link to the Audio page (a Tab stop, Enter opens it).
                Item {
                    id: chip
                    width: quick.innerW
                    height: visible ? 24 : 0
                    visible: cAudio.ok && cAudio.sinkName !== ""
                    activeFocusOnTab: true
                    Keys.onReturnPressed: quick.openPage("audio", chip)
                    Keys.onEnterPressed: quick.openPage("audio", chip)
                    Keys.onSpacePressed: quick.openPage("audio", chip)
                    Accessible.role: Accessible.Button
                    Accessible.name: cAudio.sinkName

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
                            text: cAudio.sinkName
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
                    visible: cBright.ok
                    active: cBright.ok
                    sourceComponent: Component {
                        LevelRow {
                            width: quick.innerW
                            glyph: "☼"
                            icon: "light_mode"
                            value: cBright.level
                            readout: cBright.value
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
