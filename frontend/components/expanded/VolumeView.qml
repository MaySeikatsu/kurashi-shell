import QtQuick
import "../../core"
import ".."

// The expanded view of the volume face (K24): the level as a slider (optimistic like the Bar's: the
// knob keeps the daemon's level until it answers) and the mute toggle. No audio server reads as
// such, with no level drawn (Shōjiki). Watches svc.audio only while it is on screen (Ma).
Column {
    id: view
    width: parent.width
    spacing: Theme.gap

    Watch { doc: "svc.audio" }
    readonly property var d: Store.docs["svc.audio"] || ({})
    readonly property bool avail: d.available !== false
    readonly property bool muted: d.muted === true
    readonly property real level: Math.max(0, Math.min(1, d.volume ?? 0))
    readonly property string origin: "qs:stage"
    property string errText: ""
    Refusal { id: refusal }

    Text {
        width: view.width
        color: Theme.fg
        font.pixelSize: Theme.fsTitle
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("island.volume.heading")
    }
    Row {
        width: view.width
        spacing: Theme.gap
        IconButton {
            id: mute
            glyph: view.muted ? "⊘" : "♪"
            a11y: I18n.tr(view.muted ? "island.volume.unmute" : "island.volume.mute")
            enabled: view.avail
            onClicked: {
                view.errText = ""
                Store.act("audio.mute.toggle", {}, function (done, err) {
                    if (err) view.errText = refusal.text(err, "island.volume.failed")
                })
            }
        }
        Slider {
            height: mute.height
            width: view.width - mute.width - readout.width - 2 * Theme.gap
            value: view.level
            unavailable: !view.avail
            fill: view.muted ? Theme.dim : Theme.accent
            a11y: I18n.tr("island.volume.heading")
            onMoved: v => Store.intent("audio.volume", v, view.origin)
        }
        Text {
            id: readout
            width: 64
            height: mute.height
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            color: view.muted ? Theme.dim : Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: !view.avail ? "" : (view.muted ? I18n.tr("frontend.volume.muted") : Math.round(view.level * 100) + "%")
        }
    }
    Text {
        visible: !view.avail
        width: view.width
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("frontend.volume.unavailable")
    }
    Text {
        visible: view.errText !== ""
        width: view.width
        wrapMode: Text.WordWrap
        color: Theme.error
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: view.errText
    }
}
