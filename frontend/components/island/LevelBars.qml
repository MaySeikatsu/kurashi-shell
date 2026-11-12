import QtQuick
import "../../core"

// The "now playing" level bars beside the media face's title and in the media views (W21, Apple/Capsule; K48, I111).
// Live: the audio levels of `svc.audio.spectrum` (16 bars from cava, Caelestia `services/Cava.qml`), averaged into
// `bars` groups, low frequencies on the left. Shōjiki: without the document (no cava, or cava stopped) the bars are a
// still "playing" mark, never a fake animation; while nothing plays they rest as short stubs.
// Ma: the document is watched only while `running` (the caller passes playing && on screen) and the item is visible and
// motion is on, so the daemon runs cava only then; the bars move only when a patch arrives (at most 15 a second: every
// other of cava's 30, W75; none while silent). No timer and no animation of their own.
Row {
    id: lb
    property bool running: false
    property color color: Theme.accent
    property int bars: 4
    property real maxH: 12
    property real barW: 3
    readonly property bool watching: running && visible && Theme.springOn
    Watch { doc: "svc.audio.spectrum"; active: lb.watching }
    // W75 (B118): `Store.current`, so the document can be one of the Store's quiet ones (a patch 30 times a second that
    // re-evaluated every binding on `Store.docs` in the shell); it reads `docs` until it is.
    readonly property var spec: watching ? (Store.current("svc.audio.spectrum") || ({})) : ({})
    readonly property var levelsIn: spec.available === true && Array.isArray(spec.bars) ? spec.bars : []
    // The bars take every other of cava's frames: 15 a second (each one is a whole frame of the window they are in, and of
    // the compositor's blur under it), smooth enough for a meter a few pixels tall. The first frame, the last (empty) and
    // any after a pause are taken at once; a frame left over when the stream stops (the daemon sends no repeat of the
    // silent frame) is taken a moment later, so the bars never rest on a level that is gone. (A lone Timer is a pause:
    // it starts no animation driver and wakes no window.)
    property var levels: []
    property real takenAt: 0
    onLevelsInChanged: {
        var now = Date.now()
        if (levelsIn.length === 0 || levels.length === 0 || now - takenAt >= 50) { levels = levelsIn; takenAt = now }
        else settle.restart()
    }
    Timer { id: settle; interval: 80; onTriggered: if (lb.levels !== lb.levelsIn) { lb.levels = lb.levelsIn; lb.takenAt = Date.now() } }
    readonly property bool live: watching && levels.length > 0
    // The still mark: a short staircase that reads as "playing" at a glance (the ▂▅▃▆ of a paused meter).
    readonly property var still: [0.45, 0.85, 0.6, 1.0, 0.7, 0.9]

    // The mean of group `i` of `levels`, 0..1. Groups split the levels evenly; a group is at least one level.
    function level(i) {
        var n = levels.length
        if (n === 0) return 0
        var from = Math.floor(i * n / lb.bars), to = Math.max(from + 1, Math.floor((i + 1) * n / lb.bars))
        var s = 0
        for (var k = from; k < to && k < n; k++) s += Math.max(0, Math.min(1, Number(levels[k]) || 0))
        return s / (to - from)
    }

    spacing: 2
    height: maxH
    Accessible.ignored: true
    Repeater {
        model: lb.bars
        delegate: Rectangle {
            required property int index
            anchors.bottom: parent.bottom
            width: lb.barW
            radius: lb.barW / 2
            color: lb.color
            height: lb.live ? Math.max(3, lb.maxH * lb.level(index))
                : lb.running ? Math.max(3, lb.maxH * lb.still[index % lb.still.length])
                : 3 + (index % 2) * 2
        }
    }
}
