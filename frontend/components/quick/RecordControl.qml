import QtQuick
import "../../core"

// The screen recorder (svc.recorder, K47): records or not, since when, and why it cannot (no recorder program). No page:
// its settings are on the Power page of Settings. The bar's `recorder` module shows a recording that runs. W70: the logic
// QuickPanel held.
Control {
    id: c
    mid: "recorder"
    settingsPage: "power"
    Watch { doc: "svc.recorder"; active: c.live }
    readonly property var d: Store.docs["svc.recorder"] || ({})
    readonly property bool recording: d.recording === true
    known: Store.docs["svc.recorder"] !== undefined
    label: I18n.tr("power.quick.record")
    glyph: "●"
    icon: recording ? "stop_circle" : "screen_record"
    reason: !known ? I18n.tr("power.quick.record.none")
        : d.available === false && !recording && d.reason === "power.recorder.reason.missing"
            ? I18n.tr("power.recorder.reason.missing") : ""
    forcedBy: String(d.forced_by || "")
    on: recording
    req: rqRecord
    pendingText: I18n.tr("power.quick.record.starting")
    value: recording
        ? I18n.tr("power.quick.record.since").replace("{t}", hhmm(Number(d.since_ms || Date.now())))
        : d.reason === "power.recorder.reason.failed" ? I18n.tr("power.recorder.reason.failed")
        : I18n.tr("power.quick.record.screen")
    Request {
        id: rqRecord
        value: c.recording
        start: function (to, report) {
            Store.act(to ? "recorder.start" : "recorder.stop", {}, c.cb(report, "power.quick.record.failed"))
        }
    }
}
