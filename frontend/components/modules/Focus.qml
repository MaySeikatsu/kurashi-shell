import QtQuick
import "../../core"
import "../quick"

// Module `focus` (W70): do not disturb. A click switches it; its card offers the lengths (an hour, until tomorrow).
ControlModule {
    id: m
    FocusControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    clickToggles: true
}
