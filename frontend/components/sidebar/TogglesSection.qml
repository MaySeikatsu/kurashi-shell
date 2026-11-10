import QtQuick
import Quickshell
import "../../core"
import ".."
import "../quick"
import "../expanded"

// The right sidebar's `toggles` (docs/ux/sidebar.md; W71 g, I474/I475 9, docs/ux/control-centre-modules.md): the control
// centre's switch tiles in the order `quick.tiles` gives them — the same controls (quick/*Control.qml) and the same tile
// (ControlTile) as the centre, so a value, a reason and a "connecting" read the same in both — two by two, then the mods'
// `quick.tiles` tiles (K28). The centre's wide rows (the levels, the session row) are the sidebar's own sections
// (`sliders`, `header`) and are left out here. `only`: one control's tile alone, the section a single control module
// makes (the wiring that offers it is CONTRACT-CHANGE 718). A tile's arrow, Right or its right click asks for the control's
// page (`pageRequested`): the column shows it over the sections, ← / Esc back. A control watches its document only while
// its tile is shown and the sidebar is open (it exists only then, Ma).
Item {
    id: tg
    implicitHeight: grid.height
    signal pageRequested(Component page, Item from)
    property string only: ""

    // ---- the controls: one each, live only while its tile is shown ----
    WifiControl { id: cWifi; live: tg.shows("wifi") || tg.shows("airplane") }
    AirplaneControl { id: cAir; live: tg.shows("airplane") || tg.shows("wifi") }
    BluetoothControl { id: cBt; live: tg.shows("bluetooth") }
    FocusControl { id: cFocus; live: tg.shows("focus") }
    AudioControl { id: cAudio; live: tg.shows("volume") || tg.shows("mic") }
    MicControl { id: cMic; live: tg.shows("mic") || tg.shows("volume") }
    PowerControl { id: cPower; live: tg.shows("power") }
    BrightnessControl { id: cBright; live: tg.shows("brightness") }
    CaffeineControl { id: cCaffeine; live: tg.shows("caffeine") }
    NightControl { id: cNight; live: tg.shows("nightlight") }
    RecordControl { id: cRecord; live: tg.shows("recorder") }
    DarkControl { id: cDark; live: tg.shows("darkmode") }
    readonly property var controls: ({
        wifi: cWifi, bluetooth: cBt, focus: cFocus, volume: cAudio, mic: cMic, power: cPower, brightness: cBright,
        caffeine: cCaffeine, nightlight: cNight, recorder: cRecord, darkmode: cDark, airplane: cAir
    })
    readonly property var aliases: ({ audio: "volume" })

    // ---- which tiles: `quick.tiles` (the centre's, its switch tiles), or the one control of `only` ----
    Watch { doc: "config" }
    readonly property var cfgTiles: {
        var v = ((Store.docs["config"] || {}).values || {})["quick.tiles"]
        return v && Array.isArray(v.value) ? v.value : null
    }
    readonly property var ids: {
        if (only !== "") return controls[aliases[only] || only] ? [aliases[only] || only] : []
        var src = cfgTiles !== null ? cfgTiles : ["wifi", "bluetooth", "focus", "volume", "power", "brightness", "caffeine",
            "nightlight", "recorder", "darkmode"]
        var out = []
        for (var i = 0; i < src.length; i++) {
            var id = aliases[src[i]] || src[i]
            if (controls[id] !== undefined && out.indexOf(id) < 0) out.push(id)
        }
        return out
    }
    function shows(id) { return ids.indexOf(id) >= 0 }
    // Test only (KURASHI_QUICK_LOG=1, frontend/test-quick-modules.sh): the tiles shown, in order.
    readonly property bool testLog: Quickshell.env("KURASHI_QUICK_LOG") === "1"
    onIdsChanged: if (testLog) console.log("sidebar-tiles " + ids.join(","))
    Component.onCompleted: if (testLog) console.log("sidebar-tiles " + ids.join(","))

    // ---- the pages: the centre's, with the controls' shared requests ----
    Component { id: wifiC; WifiPage { live: true; wifiReq: cWifi.req; airReq: cAir.req; joinReq: cWifi.joinReq } }
    Component { id: btC; BluetoothPage {} }
    Component { id: focusC; FocusPage { dndReq: cFocus.req } }
    Component { id: audioC; AudioPage { soundReq: cAudio.req; sinkReq: cAudio.sinkReq; micReq: cMic.req; srcReq: cMic.sourceReq } }
    Component { id: powerC; PowerPage { profReq: cPower.profileReq } }
    Component { id: displayC; DisplayPage {} }
    Component { id: nightC; NightPage { nightReq: cNight.req } }
    Component { id: caffeineC; CaffeinePage { ctl: cCaffeine } }
    Component { id: darkC; ControlPage { ctl: cDark } }
    Component { id: recorderC; RecorderPage { ctl: cRecord } }
    readonly property var pages: ({
        wifi: wifiC, bluetooth: btC, focus: focusC, audio: audioC, power: powerC, display: displayC, night: nightC,
        caffeine: caffeineC, dark: darkC, recorder: recorderC
    })
    // (kept for the column's callers: the sound page's requests)
    readonly property var micReq: cMic.req
    readonly property var sinkReq: cAudio.sinkReq

    readonly property int cols: Theme.decor("quick.tiles", "wide") === "rows" || only !== "" ? 1 : 2
    readonly property real cellW: cols > 1 ? (width - Theme.gap) / 2 : width
    SlotHost {
        id: tileSlot
        slot: "quick.tiles"
        layout: "cells"
        cellWidth: tg.cellW
        cellHeight: 56
    }
    function cells() {
        var out = []
        for (var c = 0; c < tiles.count; c++) out.push(tiles.itemAt(c))
        for (var i = 0; i < modCells.count; i++) {
            var cell = modCells.itemAt(i), t = cell !== null ? cell.tile : null
            out.push(t !== null && t !== undefined && t.isTile === true ? t : null)
        }
        return out
    }

    Grid {
        id: grid
        width: tg.width
        columns: tg.cols
        spacing: tg.cols > 1 ? Theme.gap : 0
        // Up and Down move within a column, Left and Right between the two (a plain contribution's cell is skipped).
        Keys.onPressed: event => {
            var cs = tg.cells(), i = -1
            for (var k = 0; k < cs.length; k++) if (cs[k] !== null && cs[k].activeFocus) i = k
            if (i < 0) return
            var to = -1
            switch (event.key) {
            case Qt.Key_Up: to = i >= tg.cols ? i - tg.cols : -1; break
            case Qt.Key_Down: to = i + tg.cols < cs.length ? i + tg.cols : -1; break
            case Qt.Key_Left: to = tg.cols > 1 && i % 2 === 1 ? i - 1 : -1; break
            case Qt.Key_Right: to = tg.cols > 1 && i % 2 === 0 ? i + 1 : -1; break
            default: return
            }
            if (to >= 0 && cs[to] !== null) cs[to].forceActiveFocus()
            event.accepted = true
        }
        Repeater {
            id: tiles
            model: tg.ids
            delegate: ControlTile {
                id: tile
                required property string modelData
                readonly property string mid: modelData
                width: tg.cellW
                ctl: tg.controls[modelData] || null
                onPageRequested: if (ctl && tg.pages[ctl.page]) tg.pageRequested(tg.pages[ctl.page], tile)
                onSecondaryRequested: if (ctl && ctl.settingsPage !== "")
                    Store.act("settings.open", { page: ctl.settingsPage }, function () {})
            }
        }
        Repeater {
            id: modCells
            model: tg.only === "" ? tileSlot.entries : []
            delegate: tileSlot.cell
        }
    }
}
