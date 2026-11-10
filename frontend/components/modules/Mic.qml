import QtQuick
import "../../core"
import "../quick"

// Module `mic` (W70): the microphone. A click opens its card, the sound page with the inputs (W71; or mutes, quick.click.mic).
ControlModule {
    id: m
    MicControl { id: c; live: m.live }
    ctl: c
}
