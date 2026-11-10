import QtQuick
import "../../core"
import "../quick"

// Module `focus` (W70): do not disturb. A click opens its card, the lengths (an hour, until tomorrow); W71: or switches it.
ControlModule {
    id: m
    FocusControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
}
