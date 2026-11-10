import QtQuick
import "../../core"
import "../quick"

// Module `bluetooth` (W70): the adapter, and whether a device is connected. A click opens its card, the devices
// (switching it off would drop the headphones by a slip).
ControlModule {
    id: m
    BluetoothControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
}
