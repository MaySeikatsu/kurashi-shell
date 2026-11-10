import QtQuick
import "../../core"
import "../quick"

// Module `darkmode` (W70): dark or light. A click switches the scheme outright (a mode that followed the system or
// the wallpaper is left for the chosen one); it has no page.
ControlModule {
    id: m
    DarkControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    clickToggles: true
}
