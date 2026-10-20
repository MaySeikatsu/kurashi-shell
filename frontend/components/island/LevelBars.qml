import QtQuick
import "../../core"

// The "now playing" level bars beside the media face's title and in the media views (W21, Apple/Capsule; K48, I111).
// Live: the audio levels of `svc.audio.spectrum` (16 bars from cava, Caelestia `services/Cava.qml`), averaged into
// `bars` groups, low frequencies on the left. Shōjiki: without the document (no cava, or cava stopped) the bars are a
// still "playing" mark, never a fake animation; while nothing plays they rest as short stubs.
// Ma: the document is watched only while `running` (the caller passes playing && on screen) and the item is visible and
// motion is on, so the daemon runs cava only then; the bars move only when a patch arrives (at most 30 a second, none
// while silent). No timer and no animation of their own.
Row {
    id: lb
    property bool running: false
    property color color: Theme.accent
    property int bars: 4
    property real maxH: 12
    property real barW: 3
    readonly property bool watching: running && visible && Theme.springOn
    Watch { doc: "svc.audio.spectrum"; active: lb.watching }
    readonly property var spec: watching ? (Store.docs["svc.audio.spectrum"] || ({})) : ({})
    readonly property var levels: spec.available === true && Array.isArray(spec.bars) ? spec.bars : []
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
