import QtQuick
import "../../core"
import "../quick"

// Module `nightlight` (W70): night light. A click switches it; its card has the warmth and the schedule.
ControlModule {
    id: m
    NightControl { id: c; live: m.live }
    ctl: c
    clickToggles: true
}
