import QtQuick
import "../../core"
import ".."
import "../quick"

// Module `volume` — sound (W71 c, I475 5): the one sound module, what `audio` (W70: the output as a switch and a card)
// and `volume` (the level as a slider) were. The output's mark (muted, or the level in three steps) and its level after
// it (dim while muted), then the slider; a click on it opens its card, the outputs, the inputs and what plays (the
// user, on #46; `quick.click.volume = switch`: mutes, as the media key does); the wheel steps the level by 5 % anywhere on it; hover opens the card as
// `bar.hover` says. `audio` in a zone list is the same module (ModuleHost), so a config that names either keeps working.
// A level is shown only for audio the daemon reports (no document, or `available: false`, is no level: Shōjiki, B2).
// Bar fit: elastic while it has a level (the level's text gives way first); compact is the mark alone (a click mutes,
// the wheel steps). In a column the mark stands over the upright slider.
ControlModule {
    id: m
    AudioControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    defaultClick: "switch"
    valueText: c.ok ? c.pct + " %" : ""
    valueDim: c.muted
    wheels: true
    // A notch is one 5 % step from the last value sent, so fast scrolling loses no steps before the echo; the echo resets.
    property real target: -1
    readonly property real daemonLevel: c.level
    onDaemonLevelChanged: target = -1
    // Each mutation names this control (intents' origin: the slider ignores its own echo while dragging).
    readonly property string origin: "qs:" + m.output + ":volume:" + Math.floor(Math.random() * 1e6)
    function step(dy) {
        if (dy === 0 || !c.ok) return
        var base = target >= 0 ? target : c.level
        target = Math.max(0, Math.min(1, base + (dy > 0 ? 0.05 : -0.05)))
        Store.intent("audio.volume", target, origin)
    }
    onWheeled: dy => step(dy)
    readonly property string levelA11y: !c.ok ? I18n.tr("frontend.volume.unavailable")
        : (c.muted ? I18n.tr("frontend.volume.muted") : I18n.tr("frontend.volume.level").replace("{pct}", c.pct))

    // The slider (the module's other half): after the level in a row, under the mark in a column.
    tailW: c.ok ? 110 + Theme.gap : 0
    tailH: c.ok ? 110 : 0
    tail: Component {
        Item {
            Slider {
                id: sl
                anchors.centerIn: parent
                width: 110
                rotation: m.vertical ? -90 : 0
                value: c.level
                unavailable: !c.ok
                fill: c.muted ? Theme.dim : Theme.accent
                a11y: m.levelA11y
                onMoved: v => { m.target = -1; Store.intent("audio.volume", v, m.origin) }
                // (B71: a touchpad's and the virtual pointer's wheel too, as the module's own)
                WheelHandler {
                    enabled: c.ok
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => m.step(event.angleDelta.y)
                }
            }
        }
    }
}
