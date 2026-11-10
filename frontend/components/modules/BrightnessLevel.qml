import QtQuick
import "../../core"
import ".."
import "../quick"

// Module `brightness_level` (W71 d, I475 8): the display's brightness as a level — the mark, the percent and the slider,
// the control centre's brightness row pinned to a bar (the sound level's twin is `volume` itself). A click on the mark
// opens its card (the display page); the wheel steps 5 %. Without a backlight it is the dim mark alone, inert, and says
// why (its accessible name, its card). Compact: the mark; in a column the mark over the upright slider.
ControlModule {
    id: m
    BrightnessControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    valueText: c.value
    wheels: true
    property real target: -1
    readonly property real daemonLevel: c.level
    onDaemonLevelChanged: target = -1
    readonly property string origin: "qs:" + m.output + ":brightness_level:" + Math.floor(Math.random() * 1e6)
    function step(dy) {
        if (dy === 0 || !c.ok) return
        var base = target >= 0 ? target : c.level
        target = Math.max(0, Math.min(1, base + (dy > 0 ? 0.05 : -0.05)))
        c.set(target, origin)
    }
    onWheeled: dy => step(dy)
    tailW: c.ok ? 110 + Theme.gap : 0
    tailH: c.ok ? 110 : 0
    tail: Component {
        Item {
            Slider {
                anchors.centerIn: parent
                width: 110
                rotation: m.vertical ? -90 : 0
                value: c.level
                a11y: I18n.tr("island.brightness.heading")
                onMoved: v => { m.target = -1; c.set(v, m.origin) }
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => m.step(event.angleDelta.y)
                }
            }
        }
    }
}
