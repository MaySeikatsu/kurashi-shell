import QtQuick
import "../../core"

// Sound out (svc.audio): the default output, its level and mute, and the requests to mute and to choose the output; the
// page lists the outputs, the inputs and what plays (AudioPage). W70: the logic QuickPanel held.
Control {
    id: c
    mid: "audio"
    page: "audio"
    Watch { doc: "svc.audio"; active: c.live }
    readonly property var d: Store.docs["svc.audio"] || ({})
    readonly property bool ok: d.available === true
    readonly property bool muted: d.muted === true
    readonly property var sink: defaultOf(ok ? d.sinks : null)
    readonly property string sinkName: sink ? String(sink.description || sink.name || "") : ""
    readonly property real level: ok ? Math.max(0, Math.min(1, Number(d.volume || 0))) : 0
    readonly property int pct: Math.round(Number(d.volume || 0) * 100)
    known: Store.docs["svc.audio"] !== undefined
    label: I18n.tr("island.quick.tile.audio")
    glyph: "♪"
    icon: muted ? "volume_off" : "volume_up"
    // A bar's mark: muted, or the level in three steps.
    readonly property string glanceIcon: muted ? "volume_off" : pct <= 0 ? "volume_mute" : pct < 50 ? "volume_down" : "volume_up"
    reason: ok ? "" : I18n.tr("island.quick.tile.no_audio")
    forcedBy: String(d.forced_by || "")
    on: !muted
    req: rqMute
    value: muted ? I18n.tr("island.quick.status.muted") : pct + " %"
    readonly property string statusText: !ok ? I18n.tr("island.quick.status.audio_unavailable")
        : muted ? value : (sinkName !== "" ? sinkName + " " : "") + value

    function defaultOf(list) {
        if (!list) return null
        for (var i = 0; i < list.length; i++)
            if (list[i]["default"] === true) return list[i]
        return null
    }

    property var sinkReq: rqSink
    Request {
        id: rqMute
        value: !c.muted
        start: function (to, report) { Store.act("audio.mute.toggle", {}, c.cb(report, "island.quick.audio.failed")) }
    }
    Request {
        id: rqSink
        value: c.sink !== null ? c.sink.id : null
        start: function (to, report) { Store.act("audio.sink.default", {id: to}, c.cb(report, "island.quick.audio.failed")) }
    }
}
