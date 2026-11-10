import QtQuick
import "../../../core"

// Blocks (session 28): one block per step, lit up to the level; the last lit block stands taller, as the handle. For
// the looks drawn in pixels and for anyone who likes a meter. Static.
SliderBase {
    id: sl
    property bool hovered: false
    readonly property real v: Math.max(0, Math.min(1, value))
    readonly property real len: vertical ? height : width
    readonly property real thick: vertical ? width : height
    readonly property int n: Math.max(4, Math.floor((len + 3) / 9))
    readonly property real bw: (len - (n - 1) * 3) / n
    readonly property int lit: v <= 0 ? 0 : Math.max(1, Math.round(v * n))
    Item {
        id: body
        width: sl.len; height: sl.thick
        anchors.centerIn: parent
        rotation: sl.vertical ? -90 : 0
        Repeater {
            model: sl.n
            Rectangle {
                required property int index
                readonly property bool on: index < sl.lit
                readonly property bool head: index === sl.lit - 1
                x: index * (sl.bw + 3)
                width: sl.bw
                height: Math.min(body.height, head ? (sl.pressed ? 18 : 16) : (on ? 12 : 8))
                y: Math.round((body.height - height) / 2)
                radius: Math.min(1.5, Theme.rFull)
                color: on ? Theme.accent : Theme.selected
                opacity: on ? (head ? 1 : 0.55 + 0.45 * (index + 1) / Math.max(1, sl.lit)) : 1
            }
        }
    }
}
