import QtQuick
import "../../core"

// The "now playing" level bars beside the media face's title (W21, Apple/Capsule). Decorative: there is no audio level in
// svc.media, so they say "playing", not how loud. Ma: they move only while `running` (the caller passes playing && the face
// is live) and Theme.springOn; otherwise they rest as short stubs. A Timer at 10 Hz steps them (no per-frame animation),
// so a playing island costs ten frames a second, not sixty.
Row {
    id: lb
    property bool running: false
    property color color: Theme.accent
    property int bars: 4
    property real maxH: 12
    readonly property bool moving: running && Theme.springOn
    property int tick: 0
    spacing: 2
    height: maxH
    Timer {
        interval: 100
        repeat: true
        running: lb.moving
        onTriggered: lb.tick++
    }
    Repeater {
        model: lb.bars
        delegate: Rectangle {
            required property int index
            anchors.bottom: parent.bottom
            width: 3
            radius: 1.5
            color: lb.color
            // A few out-of-step sines: lively without looking like a meter that means something.
            readonly property real wave: 0.5 + 0.5 * Math.sin(lb.tick * (0.9 + index * 0.37) + index * 1.7)
            height: lb.moving ? Math.max(3, lb.maxH * (0.25 + 0.75 * wave)) : 3 + (index % 2) * 2
        }
    }
}
