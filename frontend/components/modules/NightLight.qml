import QtQuick
import "../../core"
import "../quick"

// Module `nightlight` (W70): night light. A click opens its card, the warmth and the schedule (W71; or switches it).
ControlModule {
    id: m
    NightControl { id: c; live: m.live }
    ctl: c
}
