import QtQuick
import "../../core"

// Keep awake (svc.idle `caffeine`, K47, docs/ux/power.md): the screen stays on while it is on. It says who else keeps the
// screen awake, and when idle actions are off altogether. No page: its settings are on the Power page of Settings.
// W70: the logic QuickPanel held.
Control {
    id: c
    mid: "caffeine"
    settingsPage: "power"
    Watch { doc: "svc.idle"; active: c.live }
    readonly property var d: Store.docs["svc.idle"] || ({})
    known: Store.docs["svc.idle"] !== undefined
    label: I18n.tr("power.quick.caffeine")
    glyph: "☕"
    icon: "coffee"
    reason: !known ? I18n.tr("power.quick.caffeine.no_idle") : d.reason ? I18n.tr(String(d.reason)) : ""
    forcedBy: String(d.forced_by || "")
    on: d.caffeine === true
    req: rqCaffeine
    value: on ? I18n.tr("power.quick.caffeine.on")
        : d.enabled === false ? I18n.tr("power.quick.caffeine.idle_off")
        : d.inhibited === true && (d.inhibitors || []).length > 0
            ? I18n.tr("power.quick.caffeine.kept_by").replace("{who}", String(d.inhibitors[0].who || ""))
        : I18n.tr("island.quick.off")
    Request {
        id: rqCaffeine
        value: c.d.caffeine === true
        start: function (to, report) { Store.act("idle.caffeine", {on: to}, c.cb(report, "power.quick.failed")) }
    }
}
