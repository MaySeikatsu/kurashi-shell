import QtQuick
import "../../core"

// Power (svc.power): the battery, the time left, the power profile; the tile's switch is the power saver (when the
// daemon offers that profile), the page lists the profiles (PowerPage). W70: the logic QuickPanel held.
Control {
    id: c
    mid: "power"
    page: "power"
    Watch { doc: "svc.power"; active: c.live }
    readonly property var d: Store.docs["svc.power"] || ({})
    readonly property bool ok: d.available === true
    readonly property bool battery: d.present === true && d.percent !== undefined
    readonly property int percent: battery ? Math.round(Number(d.percent)) : 0
    readonly property bool charging: String(d.state || "") === "charging"
    readonly property bool saver: d.profile === "power-saver"
    readonly property bool saverOffered: (d.profiles || []).indexOf("power-saver") >= 0
    known: Store.docs["svc.power"] !== undefined
    label: I18n.tr("island.quick.tile.power")
    glyph: "⚡"
    icon: saver ? "energy_savings_leaf" : "bolt"
    // The battery's mark in seven steps, or charging ("" without a battery).
    readonly property string batteryIcon: !battery ? ""
        : charging ? "battery_charging_full"
        : Number(d.percent) >= 95 ? "battery_full"
        : "battery_" + Math.max(0, Math.min(6, Math.floor(Number(d.percent) / 100 * 7))) + "_bar"
    // A bar's mark: the battery while there is one, else the profile's.
    readonly property string glanceIcon: battery ? batteryIcon : icon
    reason: ok ? "" : I18n.tr("island.quick.tile.no_power")
    forcedBy: String(d.forced_by || "")
    on: saver
    toggles: saverOffered
    req: rqSaver
    value: battery ? percent + " %"
        : (String(d.profile || "") !== "" ? profileLabel(String(d.profile)) : I18n.tr("island.quick.power.ac"))
    readonly property string statusText: !ok ? I18n.tr("island.quick.status.power_unavailable")
        : battery ? percent + " %" + (timeText() !== "" ? " · " + timeText() : "")
        : value

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
        if (d.time_to_empty_s !== undefined)
            return I18n.tr("island.quick.power.to_empty").replace("{t}", duration(d.time_to_empty_s))
        if (d.time_to_full_s !== undefined)
            return I18n.tr("island.quick.power.to_full").replace("{t}", duration(d.time_to_full_s))
        return ""
    }

    property var profileReq: rqProfile
    Request {
        id: rqProfile
        value: c.d.profile !== undefined ? c.d.profile : null
        start: function (to, report) { Store.act("power.profile", {name: to}, c.cb(report, "island.quick.power.failed")) }
    }
    Request {
        id: rqSaver
        value: c.saver
        start: function (to, report) {
            Store.act("power.profile", {name: to ? "power-saver" : "balanced"}, c.cb(report, "island.quick.power.failed"))
        }
    }
}
