import QtQuick
import "../../core"
import "../quick"

// Module `wifi` (W70): the network the machine is on — the radio's mark, a wired or VPN link's, and (W71, I475 4) the
// Wi-Fi network's name after it, elided to the bar's room. A click opens its card, the Wi-Fi page (the networks);
// switching the radio off from the bar would drop the link by a slip.
ControlModule {
    id: m
    WifiControl { id: c; live: m.live }
    ctl: c
    glanceIcon: c.glanceIcon
    glanceGlyph: c.glanceGlyph
    // (a wired or VPN link says itself by its mark; no name while the radio is off or not connected)
    valueText: c.wifiOn && c.primary !== null && c.primary.kind === "wifi" ? c.primaryName : ""
}
