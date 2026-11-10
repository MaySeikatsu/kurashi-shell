import QtQuick
import "../../core"
import "../quick"

// Module `airplane` (W70): airplane mode. A click switches it (the module is there for that); its card is the Wi-Fi
// page, where the radios are. A daemon that does not report it leaves the module inert, saying so.
ControlModule {
    id: m
    AirplaneControl { id: c; live: m.live }
    ctl: c
    clickToggles: true
}
