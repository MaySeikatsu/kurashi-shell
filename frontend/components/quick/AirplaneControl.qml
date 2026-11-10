import QtQuick
import "../../core"

// Airplane mode (svc.network `airplane`, W13): every radio off at once. A daemon that does not report it has none: the
// control is then inert and says so. It has no page of its own; the Wi-Fi page shows its switch.
Control {
    id: c
    mid: "airplane"
    page: "wifi"
    Watch { doc: "svc.network"; active: c.live }
    readonly property var d: Store.docs["svc.network"] || ({})
    readonly property bool offered: typeof d.airplane === "boolean"
    known: Store.docs["svc.network"] !== undefined
    label: I18n.tr("island.quick.wifi.airplane")
    glyph: "✈"
    icon: "flight"
    reason: offered ? "" : I18n.tr("quick.airplane.none")
    forcedBy: String(d.forced_by || "")
    on: d.airplane === true
    req: rqAir
    value: I18n.tr(on ? "island.quick.on" : "island.quick.off")
    Request {
        id: rqAir
        value: c.d.airplane === true
        start: function (to, report) { Store.act("network.airplane", {on: to}, c.cb(report, "island.quick.wifi.airplane_failed")) }
    }
}
