import QtQuick
import "../../core"
import "../quick"

// Module `darkmode` (W70): dark or light. A click opens its card (W71: its switch and the scheme's choices); set to switch
// (quick.click.darkmode) it writes the scheme outright (a mode that followed the system or the wallpaper is left).
ControlModule {
    id: m
    DarkControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
}
