import QtQuick
import "../../core"
import "../quick"

// Module `mic` (W70): the microphone. A click mutes or unmutes it; its card is the sound page, with the inputs.
ControlModule {
    id: m
    MicControl { id: c; live: m.live }
    ctl: c
    clickToggles: true
}
