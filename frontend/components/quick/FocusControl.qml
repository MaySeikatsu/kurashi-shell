import QtQuick
import "../../core"

// Focus, do not disturb (svc.notifications `dnd`, `dnd_until`): on, on until a time, or off; the page offers the lengths
// (FocusPage). W70: the logic QuickPanel held.
Control {
    id: c
    mid: "focus"
    page: "focus"
    Watch { doc: "svc.notifications"; active: c.live }
    readonly property var d: Store.docs["svc.notifications"] || ({})
    readonly property bool dnd: d.dnd === true
    readonly property bool timed: typeof d.dnd_until === "number"
    known: Store.docs["svc.notifications"] !== undefined
    label: I18n.tr("island.quick.tile.focus")
    glyph: "☾"
    icon: "bedtime"
    readonly property string glanceIcon: dnd ? "do_not_disturb_on" : "do_not_disturb_off"
    reason: known ? "" : I18n.tr("island.quick.tile.no_notify")
    forcedBy: String(d.forced_by || "")
    on: dnd
    req: rqDnd
    value: !dnd ? I18n.tr("island.quick.off")
        : timed ? I18n.tr("island.quick.tile.until").replace("{t}", hhmm(d.dnd_until))
        : I18n.tr("island.quick.on")
    readonly property string statusText: timed ? I18n.tr("island.quick.status.dnd_until").replace("{t}", hhmm(d.dnd_until))
        : I18n.tr("island.quick.status.dnd_on")
    Request {
        id: rqDnd
        value: c.dnd
        start: function (to, report) { Store.act("notify.dnd", {on: to}, c.cb(report, "island.quick.focus.failed")) }
    }
}
