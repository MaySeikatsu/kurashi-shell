import QtQuick
import "../../core"
import ".."

// Module `volume`: the default sink's level as a slider (svc.audio), its wheel a 5 % step; with a chrome that groups the
// bar, the speaker glyph before it mutes on a click, as the media key does. A level is shown only for audio the daemon
// reports: no document yet, or `available: false` (no audio server), is no level, not a guessed 0 %; a muted sink keeps
// its level, drawn dim (Shōjiki, B2). In a column the slider stands upright.
ModuleBase {
    id: m
    Watch { doc: "svc.audio"; active: m.live }
    readonly property var audioDoc: Store.docs["svc.audio"]
    readonly property var audio: audioDoc || ({})
    readonly property bool usable: audioDoc !== undefined && audioDoc.available !== false
    readonly property bool muted: audio.muted === true
    readonly property real daemonVolume: audio.volume ?? 0
    readonly property string a11y: !usable ? I18n.tr("frontend.volume.unavailable")
        : (muted ? I18n.tr("frontend.volume.muted")
            : I18n.tr("frontend.volume.level").replace("{pct}", Math.round(daemonVolume * 100)))
    // Each mutation names this control (intents' origin: the slider ignores its own echo while dragging).
    readonly property string origin: "qs:" + m.output + ":" + Math.floor(Math.random() * 1e6)
    readonly property int columnH: 110
    width: vertical ? thickness : row.implicitWidth
    height: vertical ? columnH : row.implicitHeight
    slotHeights: [columnH]
    // The slider is its own tab stop while there is audio to set (arrows step it); without, the host says why.
    ownsFocus: usable
    a11yName: a11y
    function geo() { return [["slider", vertical ? sliderV : sliderH]] }

    // Wheel intents: a notch is one 5 % step from the last value sent, so fast scrolling does not lose steps while the
    // daemon's echo is still on its way; the echo resets it.
    property real target: -1
    onDaemonVolumeChanged: target = -1
    function set(v) {
        if (!usable) return
        target = -1
        Store.intent("audio.volume", v, origin)
    }
    function step(dy) {
        if (dy === 0 || !usable) return
        var base = target >= 0 ? target : daemonVolume
        target = Math.max(0, Math.min(1, base + (dy > 0 ? 0.05 : -0.05)))
        Store.intent("audio.volume", target, origin)
    }

    Row {
        id: row
        visible: !m.vertical
        spacing: Theme.pad
        // The volume's icon (chromes with groups): a click mutes, as the media key does.
        Icon {
            visible: Theme.groups && m.usable
            anchors.verticalCenter: parent.verticalCenter
            name: m.muted ? "volume_off" : "volume_up"
            glyph: m.muted ? "🔇" : "🔊"
            filled: true
            color: Theme.fg
            TapHandler { onTapped: Store.act("audio.mute.toggle") }
        }
        Slider {
            id: sliderH
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            value: m.daemonVolume
            unavailable: !m.usable
            fill: m.muted ? Theme.dim : Theme.accent
            a11y: m.a11y
            onMoved: v => m.set(v)
            WheelHandler { enabled: m.usable; onWheel: event => m.step(event.angleDelta.y) }
        }
    }
    Item {
        visible: m.vertical
        width: m.thickness
        height: m.columnH
        Slider {
            id: sliderV
            anchors.centerIn: parent
            width: 110
            rotation: -90
            value: m.daemonVolume
            unavailable: !m.usable
            fill: m.muted ? Theme.dim : Theme.accent
            a11y: m.a11y
            onMoved: v => m.set(v)
            WheelHandler { enabled: m.usable; onWheel: event => m.step(event.angleDelta.y) }
        }
    }
}
