import QtQuick
import Quickshell
import "../../core"
import ".."

// The Wi-Fi page (docs/ux/quick-settings.md, Design 2): the switch, airplane mode, and up to eight networks of
// svc.network.scan. The scan document is watched only while this page is on screen (`live`, Ma): the daemon scans only
// then. A saved network joins (`network.connect`); the others are refused by the daemon with its reason, shown here
// (no password entry yet). The active network disconnects from its own row. Requests come from QuickPanel, shared with
// the tile. The lists are ListModels updated in place, so the focus stays where the user put it.
Column {
    id: wifi
    // W71: the module ids whose options the page lists (the module that opened it; none from the tiles).
    property var optionIds: []
    width: parent.width
    spacing: Theme.gap
    property bool live: false
    property var wifiReq: null
    property var airReq: null
    property var joinReq: null
    signal backRequested()

    function focusFirst() { header.forceActiveFocus() }

    Watch { doc: "svc.network.scan"; active: wifi.live }
    readonly property var net: Store.docs["svc.network"] || ({})
    readonly property var scan: Store.docs["svc.network.scan"] || ({})
    readonly property bool avail: typeof net.state === "string" && net.state !== "unavailable"
    readonly property bool hasAirplane: typeof net.airplane === "boolean"
    readonly property bool loading: Object.keys(scan).length === 0
    // W71 (the user's review, Shōjiki): NetworkManager may report the radio enabled on a machine with no Wi-Fi device. Only the
    // scan says so (svc.network has no such field yet: CONTRACT-CHANGE 713): the switch then draws off and inert, and the
    // reason stands once, under the switch it explains — not under airplane mode, not again at the list's end.
    readonly property bool noDevice: scan.available === false && String(scan.reason || "") === "error.network.no_wifi_device"
    // Test only (KURASHI_QUICK_LOG=1, test-quick-sections.sh): what the switch draws when the scan says there is no device.
    readonly property bool testLog: Quickshell.env("KURASHI_QUICK_LOG") === "1"
    onNoDeviceChanged: if (testLog) Qt.callLater(function () {
        console.log("quick-wifi nodevice " + wifi.noDevice + " checked " + sw.checked + " enabled " + sw.enabled) })

    // The list: the scan's networks (the daemon's order: the active one first, then by strength), eight at most.
    ListModel { id: nets }
    function lit(strength) { return strength > 0 ? Math.min(4, Math.ceil(strength / 25)) : 0 }
    function syncNets() {
        var list = (scan.networks || []).slice(0, 8)
        for (var i = 0; i < list.length; i++) {
            var n = list[i]
            var sec = n.secure === true ? I18n.tr("island.quick.wifi.secured") : I18n.tr("island.quick.wifi.open")
            var line = n.active === true ? I18n.tr("island.quick.wifi.line_active").replace("{s}", sec)
                : n.known === true ? I18n.tr("island.quick.wifi.line_saved").replace("{s}", sec)
                : I18n.tr("island.quick.wifi.line_new").replace("{s}", sec)
            var r = {ssid: String(n.ssid || ""), line: line, strength: lit(Number(n.strength || 0)), active: n.active === true}
            if (i < nets.count) nets.set(i, r)
            else nets.append(r)
        }
        while (nets.count > list.length) nets.remove(nets.count - 1)
    }
    onScanChanged: syncNets()
    Component.onCompleted: syncNets()

    function join(ssid, active) {
        if (wifi.joinReq !== null) wifi.joinReq.begin(active ? null : ssid)
    }

    PageHeader {
        id: header
        title: I18n.tr("island.quick.tile.wifi")
        backName: I18n.tr("island.quick.back")
        onBack: wifi.backRequested()
    }
    Row {
        width: wifi.width
        spacing: Theme.gap
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: parent.width - sw.width - Theme.gap
            anchors.verticalCenter: sw.verticalCenter
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.quick.network.heading")
        }
        ToggleSwitch {
            id: sw
            checked: wifi.net.wifi_enabled === true && !wifi.noDevice
            enabled: wifi.avail && !wifi.noDevice && !(wifi.wifiReq !== null && wifi.wifiReq.pending)
            label: I18n.tr("island.quick.network.heading")
            onToggled: on => { if (wifi.wifiReq !== null) wifi.wifiReq.begin(on) }
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: wifi.noDevice
        width: wifi.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("error.network.no_wifi_device")
    }
    StateLine {
        width: wifi.width
        req: wifi.wifiReq
        pendingText: I18n.tr("island.quick.connecting")
    }
    Row {
        visible: wifi.hasAirplane
        width: wifi.width
        spacing: Theme.gap
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            width: parent.width - air.width - Theme.gap
            anchors.verticalCenter: air.verticalCenter
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("island.quick.wifi.airplane")
        }
        ToggleSwitch {
            id: air
            checked: wifi.net.airplane === true
            enabled: wifi.avail && !(wifi.airReq !== null && wifi.airReq.pending)
            label: I18n.tr("island.quick.wifi.airplane")
            onToggled: on => { if (wifi.airReq !== null) wifi.airReq.begin(on) }
        }
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: !wifi.hasAirplane
        width: wifi.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.wifi.airplane_unavailable")
    }
    StateLine {
        width: wifi.width
        req: wifi.airReq
        pendingText: I18n.tr("island.quick.changing")
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
        visible: wifi.scan.available !== false && !wifi.noDevice
        width: wifi.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.quick.wifi.networks")
    }
    Repeater {
        model: nets
        delegate: ChoiceRow {
            required property string ssid
            required property string line
            required property int strength
            required property bool active
            width: wifi.width
            title: ssid
            sub: line
            bars: strength
            checked: active
            pending: wifi.joinReq !== null && wifi.joinReq.want === (active ? null : ssid)
            pendingText: I18n.tr("island.quick.connecting")
            onActivated: wifi.join(ssid, active)
        }
    }
    StateLine {
        width: wifi.width
        req: wifi.joinReq
        pendingText: I18n.tr("island.quick.connecting")
    }
    // Why no list: the scan still answers, Wi-Fi is off, or nothing is in range. The daemon's reason is an i18n key.
    LoadingText {
        visible: !wifi.noDevice && (wifi.scan.available === false || wifi.loading || (wifi.scan.available === true && nets.count === 0))
        width: wifi.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        loading: wifi.loading
        words: wifi.loading ? I18n.tr("island.quick.wifi.scanning")
            : wifi.scan.available === false ? I18n.tr(String(wifi.scan.reason || "island.quick.network.unavailable"))
            : I18n.tr("island.quick.wifi.none")
    }
    // W71 (I475 3): the options of the module that opened the page (its click among them), as its menu lists them;
    // what the page draws itself is left out.
    ModuleOptions {
        width: wifi.width
        mids: wifi.optionIds
        skip: []
    }
}
