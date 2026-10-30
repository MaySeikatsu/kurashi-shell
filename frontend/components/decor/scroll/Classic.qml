import QtQuick
import "../../../core"
import ".."

// Classic (W53.1): a bevel-era scroll bar — `[decor] scroll.width` px (16 in 9x, Wine's ScrollWidth), a track dithered in
// face and highlight, a raised thumb (8 px at least), and with `scroll.arrows` two raised arrow buttons of the bar's width
// with a black triangle on whole pixels; an arrow sinks while held and scrolls a line (`step`), repeating while held as 9x
// did (the timer runs only while a button is down). Static otherwise.
ScrollBase {
    id: sb
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool vert: orientation === Qt.Vertical
    readonly property int thick: vert ? width : height
    readonly property bool arrows: Theme.decor("scroll.arrows", false) === true
    readonly property int btn: arrows ? thick : 0
    readonly property real track: Math.max(0, (vert ? height : width) - 2 * btn)
    readonly property real thumbLen: Math.max(8, track * Math.min(1, size))
    readonly property real thumbAt: btn + Math.max(0, Math.min(track - thumbLen, track * position))

    Checker {
        x: sb.vert ? 0 : sb.btn
        y: sb.vert ? sb.btn : 0
        width: sb.vert ? sb.width : sb.track
        height: sb.vert ? sb.track : sb.height
    }
    // The thumb (none when everything shows, as 9x hid it).
    Item {
        visible: sb.size < 1
        x: sb.vert ? 0 : Math.round(sb.thumbAt)
        y: sb.vert ? Math.round(sb.thumbAt) : 0
        width: sb.vert ? sb.width : Math.round(sb.thumbLen)
        height: sb.vert ? Math.round(sb.thumbLen) : sb.height
        Rectangle { anchors.fill: parent; color: Theme.surface }
        BevelEdge { anchors.fill: parent; w: sb.hair }
    }
    component Arrow: Item {
        id: ar
        // -1: up or left, +1: down or right.
        property int dir: -1
        readonly property bool down: hit.pressed && hit.containsMouse
        width: sb.vert ? sb.width : sb.btn
        height: sb.vert ? sb.btn : sb.height
        Rectangle { anchors.fill: parent; color: Theme.surface }
        BevelEdge { anchors.fill: parent; w: Theme.crisp(1, Screen.devicePixelRatio); sunk: ar.down }
        // A 7 × 4 triangle (rows of 7, 5, 3, 1 px), pointing along the bar.
        Item {
            x: Math.floor((ar.width - (sb.vert ? 7 : 4)) / 2) + (ar.down ? 1 : 0)
            y: Math.floor((ar.height - (sb.vert ? 4 : 7)) / 2) + (ar.down ? 1 : 0)
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    // The tip row is index 0 for up/left, 3 for down/right.
                    readonly property int k: ar.dir < 0 ? index : 3 - index
                    x: sb.vert ? 3 - k : index
                    y: sb.vert ? index : 3 - k
                    width: sb.vert ? 2 * k + 1 : 1
                    height: sb.vert ? 1 : 2 * k + 1
                    color: Theme.fg
                }
            }
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            onPressed: sb.step(ar.dir)
        }
        // Held: a pause, then a line every 50 ms (the keyboard's repeat, as 9x).
        property bool fast: false
        Timer {
            interval: ar.fast ? 50 : 400
            repeat: true
            running: hit.pressed && hit.containsMouse
            onRunningChanged: if (!running) ar.fast = false
            onTriggered: { ar.fast = true; sb.step(ar.dir) }
        }
    }
    Arrow { visible: sb.arrows; dir: -1 }
    Arrow {
        visible: sb.arrows
        dir: 1
        x: sb.vert ? 0 : sb.width - sb.btn
        y: sb.vert ? sb.height - sb.btn : 0
    }
}
