import QtQuick
import "../../core"

// The microphone (svc.audio `source`): the default input and its mute, and the requests to mute it and to choose the
// input; its page is the sound page (AudioPage), which lists the inputs. W70: the logic QuickPanel held.
Control {
    id: c
    mid: "mic"
    page: "audio"
    Watch { doc: "svc.audio"; active: c.live }
    readonly property var d: Store.docs["svc.audio"] || ({})
    readonly property bool ok: d.available === true
    readonly property var source: ok && d.source ? d.source : null
    readonly property bool muted: source !== null && source.muted === true
    readonly property string sourceName: source ? String(source.description || source.name || "") : ""
    known: Store.docs["svc.audio"] !== undefined
    label: I18n.tr("island.quick.audio.microphone")
    glyph: "🎙"
    icon: muted ? "mic_off" : "mic"
    reason: !ok ? I18n.tr("island.quick.tile.no_audio") : source === null ? I18n.tr("quick.mic.none") : ""
    forcedBy: String(d.forced_by || "")
    on: !muted
    req: rqMic
    value: muted ? I18n.tr("island.quick.status.muted")
        : source !== null && source.volume !== undefined ? Math.round(Number(source.volume) * 100) + " %"
        : I18n.tr("island.quick.on")

    property var sourceReq: rqSrc
    Request {
        id: rqMic
        value: !(c.source !== null && c.source.muted === true)
        start: function (to, report) { Store.act("audio.mic.mute.toggle", {}, c.cb(report, "island.quick.audio.mic_failed")) }
    }
    Request {
        id: rqSrc
        value: c.source !== null ? c.source.id : null
        start: function (to, report) { Store.act("audio.source.default", {id: to}, c.cb(report, "island.quick.audio.source_failed")) }
    }
}
