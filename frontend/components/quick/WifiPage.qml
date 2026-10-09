import QtQuick
import "../../core"
import ".."

// The Wi-Fi page (docs/ux/quick-settings.md, Design 2): the switch, airplane mode, and up to eight networks of
// svc.network.scan. The scan document is watched only while this page is on screen (`live`, Ma): the daemon scans only
// then. A saved network joins (`network.connect`); the others are refused by the daemon with its reason, shown here
// (no password entry yet). The active network disconnects from its own row. Requests come from QuickPanel, shared with
// the tile. The lists are ListModels updated in place, so the focus stays where the user put it.
Column {
    id: wifi
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
            checked: wifi.net.wifi_enabled === true
            enabled: wifi.avail && !(wifi.wifiReq !== null && wifi.wifiReq.pending)
            label: I18n.tr("island.quick.network.heading")
            onToggled: on => { if (wifi.wifiReq !== null) wifi.wifiReq.begin(on) }
        }
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
        visible: wifi.scan.available !== false
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
    Text {
        visible: wifi.scan.available === false || wifi.loading || (wifi.scan.available === true && nets.count === 0)
        width: wifi.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: wifi.loading ? I18n.tr("island.quick.wifi.scanning")
            : wifi.scan.available === false ? I18n.tr(String(wifi.scan.reason || "island.quick.network.unavailable"))
            : I18n.tr("island.quick.wifi.none")
    }
}
