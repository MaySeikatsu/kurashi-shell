import QtQuick
import "../../core"

// Night light (svc.nightlight, K47): on, on until or from a time on its schedule, or off; the page has the warmth and the
// schedule (NightPage). A compositor or program that cannot do it is the reason. W70: the logic QuickPanel held.
Control {
    id: c
    mid: "nightlight"
    page: "night"
    settingsPage: "power"
    Watch { doc: "svc.nightlight"; active: c.live }
    readonly property var d: Store.docs["svc.nightlight"] || ({})
    known: Store.docs["svc.nightlight"] !== undefined
    label: I18n.tr("power.night.title")
    glyph: "◐"
    icon: "nightlight"
    reason: !known ? I18n.tr("power.quick.night.none")
        : d.available === false && d.reason ? I18n.tr(String(d.reason)) : ""
    forcedBy: String(d.forced_by || "")
    on: d.enabled === true
    req: rqNight
    value: d.enabled !== true ? I18n.tr("island.quick.off")
        : String(d.schedule || "") === "always" ? I18n.tr("island.quick.on")
        : d.active === true
            ? (d.next_change ? I18n.tr("island.quick.tile.until").replace("{t}", String(d.next_change)) : I18n.tr("island.quick.on"))
        : d.next_change ? I18n.tr("power.quick.night.from").replace("{t}", String(d.next_change))
        : I18n.tr("island.quick.on")
    Request {
        id: rqNight
        value: c.d.enabled === true
        start: function (to, report) { Store.act("nightlight.toggle", {on: to}, c.cb(report, "power.quick.failed")) }
    }
}
