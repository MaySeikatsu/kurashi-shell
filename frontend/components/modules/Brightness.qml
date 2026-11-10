import QtQuick
import "../../core"
import "../quick"

// Module `brightness` (W70): the display's level in three steps. The wheel steps it by 5 %; a click opens its card,
// the level. Without a backlight it is inert and says so.
ControlModule {
    id: m
    BrightnessControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    wheels: true
    property real target: -1
    readonly property real daemonLevel: c.level
    onDaemonLevelChanged: target = -1
    readonly property string origin: "qs:" + m.output + ":brightness:" + Math.floor(Math.random() * 1e6)
    onWheeled: dy => {
        if (dy === 0 || !c.ok) return
        var base = target >= 0 ? target : c.level
        target = Math.max(0, Math.min(1, base + (dy > 0 ? 0.05 : -0.05)))
        c.set(target, origin)
    }
}
