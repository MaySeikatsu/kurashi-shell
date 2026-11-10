import QtQuick
import "../../core"
import "../quick"

// Module `power` (W70): the battery — its mark and percent — or, without one, the power profile's mark. A click
// opens its card, the profiles and the time left (which profile a click should pick is not obvious).
ControlModule {
    id: m
    PowerControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    valueText: c.battery ? c.percent + "%" : ""
}
