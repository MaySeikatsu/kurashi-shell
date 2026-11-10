import QtQuick
import "../../core"
import "../quick"

// Module `caffeine` (W70): keep awake. A click switches it; it has no page (its settings are Settings › Power, in its
// menu).
ControlModule {
    id: m
    CaffeineControl { id: c; live: m.live }
    ctl: c
    clickToggles: true
}
