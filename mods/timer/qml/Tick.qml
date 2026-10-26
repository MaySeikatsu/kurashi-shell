import QtQuick

// The timer mod's one-second clock (K73, docs/ux/timer.md "Ticking", Ma): it runs only while `wanted` (a running countdown
// is on screen), and wakes just after each whole second so the digits change on the second. `now` is the wall clock the
// views read, in Unix ms; it is current when the clock starts.
Timer {
    id: tick
    property bool wanted: false
    property real now: Date.now()
    repeat: false
    interval: 1000
    // A clock created already wanted starts here: `onWantedChanged` does not fire for the value it starts with.
    Component.onCompleted: {
        if (tick.wanted) {
            tick.now = Date.now()
            tick.interval = 1000 - (tick.now % 1000) + 2
            tick.start()
        }
    }
    onWantedChanged: {
        if (tick.wanted) {
            tick.now = Date.now()
            tick.interval = 1000 - (tick.now % 1000) + 2
            tick.start()
        } else {
            tick.stop()
        }
    }
    onTriggered: {
        tick.now = Date.now()
        if (tick.wanted) {
            tick.interval = 1000 - (tick.now % 1000) + 2
            tick.start()
        }
    }
}
