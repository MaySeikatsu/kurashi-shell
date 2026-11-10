import QtQuick
import "../../core"
import "../quick"

// Module `audio` (W70): the sound output — muted, or its level in three steps. A click mutes, as the media key
// does; the wheel steps the level by 5 %; its card lists the outputs, the inputs and what plays. The `volume` module
// is the level as a slider; this is the output as a switch and a card.
ControlModule {
    id: m
    AudioControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    clickToggles: true
    wheels: true
    // A notch is one 5 % step from the last value sent, so fast scrolling loses no steps before the echo (Volume.qml).
    property real target: -1
    readonly property real daemonLevel: c.level
    onDaemonLevelChanged: target = -1
    readonly property string origin: "qs:" + m.output + ":audio:" + Math.floor(Math.random() * 1e6)
    function step(dy) {
        if (dy === 0 || !c.ok) return
        var base = target >= 0 ? target : c.level
        target = Math.max(0, Math.min(1, base + (dy > 0 ? 0.05 : -0.05)))
        Store.intent("audio.volume", target, origin)
    }
}
