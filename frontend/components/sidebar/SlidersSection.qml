import QtQuick
import "../../core"
import ".."
import "../quick"
import "../expanded"

// The right sidebar's `sliders` (docs/ux/sidebar.md; ii `sidebarRight/QuickSliders.qml`): the output volume and, while
// there is a backlight, the brightness — the quick card's LevelRow, each move an intent — and the microphone: its
// switch and its level as the daemon reports it. The microphone level has no setter yet (no `audio.source.volume`
// intent, CONTRACT row 237), so it is a readout, not a slider that would do nothing (Shōjiki).
Column {
    id: sl
    spacing: Theme.gap
    Watch { doc: "svc.audio" }
    Watch { doc: "svc.brightness" }
    readonly property string origin: "qs:sidebar"
    readonly property var audioDoc: Store.docs["svc.audio"] || ({})
    readonly property bool audioOk: audioDoc.available === true
    readonly property bool muted: audioDoc.muted === true
    readonly property int volPct: Math.round(Number(audioDoc.volume || 0) * 100)
    readonly property var src: audioOk && audioDoc.source ? audioDoc.source : null
    readonly property bool micOn: src !== null && src.muted !== true
    readonly property var brDoc: Store.docs["svc.brightness"] || ({})
    readonly property bool brOk: brDoc.present === true
    Refusal { id: refusal }
    Request {
        id: rqMic
        value: sl.micOn
        start: function (to, report) {
            Store.act("audio.mic.mute.toggle", {}, function (done, err) {
                if (err) report(refusal.text(err, "island.quick.audio.mic_failed"))
            })
        }
    }

    LevelRow {
        width: sl.width
        glyph: "♪"
        icon: sl.muted ? "volume_off" : "volume_up"
        value: sl.audioOk ? Math.max(0, Math.min(1, Number(sl.audioDoc.volume || 0))) : 0
        readout: sl.audioOk ? (sl.muted ? I18n.tr("island.quick.status.muted") : sl.volPct + " %") : ""
        unavailable: !sl.audioOk
        a11y: I18n.tr("island.quick.level.volume")
        onMoved: v => Store.intent("audio.volume", v, sl.origin)
    }
    LevelRow {
        visible: sl.brOk
        width: sl.width
        glyph: "☼"
        icon: "light_mode"
        value: sl.brOk ? Math.max(0, Math.min(1, Number(sl.brDoc.percent || 0) / 100)) : 0
        readout: sl.brOk ? Math.round(Number(sl.brDoc.percent || 0)) + " %" : ""
        a11y: I18n.tr("island.brightness.heading")
        onMoved: v => Store.intent("brightness.set", v, sl.origin)
    }
    // The microphone: a pill of the levels' shape with its mark, its name, the level read out and the switch.
    Block {
        id: mic
        visible: sl.audioOk
        width: sl.width
        height: Theme.controlH + 10 + Theme.shadowDy
        radius: Theme.rFull
        fill: Theme.containerHigh
        readonly property real innerH: faceH - 2 * inset
        Icon {
            id: micMark
            x: 10
            width: 22
            height: mic.innerH
            name: sl.micOn ? "mic" : "mic_off"
            glyph: "◖"
            filled: sl.micOn
            size: 18
            color: sl.micOn ? Theme.accent : Theme.dim
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            x: micMark.x + micMark.width + Theme.gap
            width: micSwitch.x - x - Theme.gap
            height: mic.innerH
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
            text: rqMic.failure !== "" ? rqMic.failure
                : sl.src === null ? I18n.tr("island.quick.audio.no_input")
                : I18n.tr("island.quick.audio.microphone") + " · "
                    + (sl.micOn ? Math.round(Number(sl.src.volume || 0) * 100) + " %" : I18n.tr("island.quick.status.muted"))
        }
        ToggleSwitch {
            id: micSwitch
            x: mic.width - width - 2 * mic.inset - 12
            anchors.verticalCenter: micMark.verticalCenter
            enabled: sl.src !== null && !rqMic.pending
            checked: sl.micOn
            label: I18n.tr("island.quick.audio.microphone")
            onToggled: on => rqMic.begin(on)
        }
    }
}
