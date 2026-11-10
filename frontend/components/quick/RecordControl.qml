import QtQuick
import "../../core"

// The screen recorder (svc.recorder, K47): records or not, since when, and why it cannot (no recorder program). No page:
// its settings are on the Power page of Settings. The bar's `recorder` module shows a recording that runs. W70: the logic
// QuickPanel held.
Control {
    id: c
    mid: "recorder"
    // W71 (f): its own page, the recorder's card (RecorderPage); a click on its module while it records stops it.
    page: "recorder"
    clickStops: true
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
    // The output to record (`recorder.start {output}`); "" the daemon's choice. The card sets it before it starts.
    property string output: ""
    Request {
        id: rqRecord
        value: c.recording
        start: function (to, report) {
            Store.act(to ? "recorder.start" : "recorder.stop", to && c.output !== "" ? {output: c.output} : {},
                      c.cb(report, "power.quick.record.failed"))
        }
    }
    // The running time, "01:23" (or "1:02:03"), ticking once a second only while a recording runs and something shows it
    // (the card, the bar's module: `live`). Ma: no timer otherwise.
    property double nowMs: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: c.live && c.recording
        triggeredOnStart: true
        onTriggered: c.nowMs = Date.now()
    }
    readonly property string elapsed: {
        if (!recording) return ""
        var s = Math.max(0, Math.floor((nowMs - Number(d.since_ms || nowMs)) / 1000))
        var h = Math.floor(s / 3600), mm = Math.floor(s / 60) % 60, ss = s % 60
        return (h > 0 ? h + ":" + pad(mm) : pad(mm)) + ":" + pad(ss)
    }
}
