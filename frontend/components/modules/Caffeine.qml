import QtQuick
import "../../core"
import "../quick"

// Module `caffeine` (W70): keep awake. A click opens its card (W71: its switch, who else keeps the screen awake, its
// options; or switches it, quick.click.caffeine).
ControlModule {
    id: m
    CaffeineControl { id: c; live: m.live }
    ctl: c
}
