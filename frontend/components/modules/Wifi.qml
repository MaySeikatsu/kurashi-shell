import QtQuick
import "../../core"
import "../quick"

// Module `wifi` (W70): the network the machine is on — the radio's mark, a wired or VPN link's. A click opens its
// card, the Wi-Fi page (the networks); switching the radio off from the bar would drop the link by a slip.
ControlModule {
    id: m
    WifiControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    glanceGlyph: c.glanceGlyph
}
