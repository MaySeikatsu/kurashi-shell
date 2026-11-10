import QtQuick
import "../../core"
import "../quick"

// Module `airplane` (W70): airplane mode. A click opens its card (W71; or switches it), the Wi-Fi
// page, where the radios are. A daemon that does not report it leaves the module inert, saying so.
ControlModule {
    id: m
    AirplaneControl { id: c; live: m.live }
    ctl: c
}
