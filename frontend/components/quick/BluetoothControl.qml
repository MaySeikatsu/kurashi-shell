import QtQuick
import "../../core"

// Bluetooth (svc.bluetooth): the adapter's power and how many devices are connected; the page lists the devices
// (BluetoothPage). W70: the logic QuickPanel held.
Control {
    id: c
    mid: "bluetooth"
    page: "bluetooth"
    Watch { doc: "svc.bluetooth"; active: c.live }
    readonly property var d: Store.docs["svc.bluetooth"] || ({})
    readonly property bool ok: d.available === true
    readonly property bool powered: d.powered === true
    readonly property int connected: {
        var n = 0
        var ds = d.devices || []
        for (var i = 0; i < ds.length; i++) if (ds[i].connected === true) n++
        return n
    }
    known: Store.docs["svc.bluetooth"] !== undefined
    label: I18n.tr("island.quick.tile.bluetooth")
    glyph: "ᛒ"
    icon: powered ? "bluetooth" : "bluetooth_disabled"
    readonly property string glanceIcon: !powered ? "bluetooth_disabled" : connected > 0 ? "bluetooth_connected" : "bluetooth"
    reason: ok ? "" : I18n.tr("island.quick.tile.no_bluetooth")
    forcedBy: String(d.forced_by || "")
    on: powered
    req: rqBt
    pendingText: I18n.tr("island.quick.connecting")
    value: !powered ? I18n.tr("island.quick.off")
        : connected > 0 ? I18n.tr("island.quick.tile.connected_n").replace("{n}", String(connected))
        : I18n.tr("island.quick.on")
    Request {
        id: rqBt
        value: c.powered
        start: function (to, report) { Store.act("bluetooth.power", {on: to}, c.cb(report, "island.quick.bluetooth.failed")) }
    }
}
