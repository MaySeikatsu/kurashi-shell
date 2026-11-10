import QtQuick
import "../../core"

// Wi-Fi (svc.network): the radio, the network it is on, and the requests to switch the radio and to join or leave a
// network (W70; the logic QuickPanel held since W13). The page lists the networks (WifiPage).
Control {
    id: c
    mid: "wifi"
    page: "wifi"
    Watch { doc: "svc.network"; active: c.live }
    readonly property var d: Store.docs["svc.network"] || ({})
    readonly property bool ok: typeof d.state === "string" && d.state !== "unavailable"
    readonly property bool wifiOn: d.wifi_enabled === true
    readonly property var primary: d.primary || null
    readonly property string primaryName: primary ? String(primary.name || "") : ""
    // The signal of the link the machine is on, 0..100 (absent for a wired one or a daemon that does not say).
    readonly property int strength: primary && primary.strength !== undefined ? Number(primary.strength) : -1

    known: Store.docs["svc.network"] !== undefined
    label: I18n.tr("island.quick.tile.wifi")
    glyph: "≋"
    icon: wifiOn ? "wifi" : "wifi_off"
    // A bar's mark: the link the machine is on (wired, VPN), else the radio, off or not connected.
    readonly property string glanceIcon: !wifiOn && primary === null ? "wifi_off"
        : primary === null ? "signal_wifi_0_bar"
        : primary.kind === "ethernet" ? "lan"
        : primary.kind === "vpn" ? "vpn_key"
        : "wifi"
    readonly property string glanceGlyph: primary !== null && primary.kind === "ethernet" ? "⇄"
        : primary !== null && primary.kind === "vpn" ? "⚿" : "≋"
    reason: ok ? "" : I18n.tr("island.quick.tile.no_network")
    forcedBy: String(d.forced_by || "")
    on: wifiOn
    req: rqWifi
    pendingText: I18n.tr("island.quick.connecting")
    value: !wifiOn ? I18n.tr("island.quick.off")
        : primary === null ? I18n.tr("island.quick.status.not_connected")
        : primary.kind === "wifi" ? (primaryName !== "" ? primaryName : I18n.tr("island.quick.tile.wifi"))
        : kindLabel(String(primary.kind))
    // The status sentence's segment for the network as a whole.
    readonly property string statusText: !ok ? I18n.tr("island.quick.status.network_unavailable")
        : wifiOn ? value : I18n.tr("island.quick.status.wifi_off")

    function kindLabel(kind) {
        var k = ["wifi", "ethernet", "vpn", "bluetooth"].indexOf(kind) >= 0 ? kind : "other"
        return I18n.tr("island.quick.network.kind." + k)
    }

    property var joinReq: rqJoin
    Request {
        id: rqWifi
        value: c.wifiOn
        start: function (to, report) { Store.act("network.wifi", {on: to}, c.cb(report, "island.quick.network.failed")) }
    }
    Request {
        id: rqJoin
        value: c.primary !== null ? c.primaryName : null
        start: function (to, report) {
            if (to === null) Store.act("network.disconnect", {}, c.cb(report, "island.quick.wifi.disconnect_failed"))
            else Store.act("network.connect", {ssid: to}, c.cb(report, "island.quick.wifi.connect_failed"))
        }
    }
}
