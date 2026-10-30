import QtQuick
import "../../core"

// Text whose characters flip when they change (W21, Capsule's idle flip clock): a changed character rolls up out of its
// cell while the new one rolls in from below with a little overshoot; unchanged characters stay still. It runs once per
// change (the clock's minute), never on a timer, and only when `animate` (the face is live and motion is on) (Ma).
Row {
    id: ft
    property string text: ""
    property color color: Theme.fg
    property int pixelSize: Theme.fs
    property int weight: Theme.wRegular
    property bool animate: false
    readonly property var chars: text.split("")
    Repeater {
        model: ft.chars.length
        delegate: Item {
            id: cell
            required property int index
            readonly property string ch: ft.chars[index] ?? ""
            property string prev: ""
            property real p: 1
            width: Math.max(now.implicitWidth, cell.p < 1 ? old.implicitWidth : 0)
            height: now.implicitHeight
            clip: true
            onChChanged: {
                if (!ft.animate || !Theme.springOn) { flip.stop(); prev = ch; p = 1; return }
                flip.stop()
                p = 0
                flip.start()
            }
            Component.onCompleted: prev = ch
            NumberAnimation {
                id: flip
                target: cell
                property: "p"
                from: 0
                to: 1
                // I193 (user, session 13): the minute flip is the only idle commit, so it is capped at 300 ms (BENCH names it).
                duration: Math.min(300, Theme.stdMs + 80)
                easing.type: Easing.OutBack
                easing.overshoot: Theme.overshoot
                onFinished: cell.prev = cell.ch
            }
            Text {
                id: old
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                visible: cell.p < 1 && cell.prev !== cell.ch
                y: -cell.height * Math.min(1, cell.p)
                opacity: 1 - Math.min(1, cell.p)
                text: cell.prev
                color: ft.color
                font.pixelSize: ft.pixelSize
                font.weight: ft.weight
                font.family: Theme.fam(text, Theme.families)
                font.features: { "tnum": 1 }
            }
            Text {
                id: now
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                y: cell.height * (1 - cell.p)
                text: cell.ch
                color: ft.color
                font.pixelSize: ft.pixelSize
                font.weight: ft.weight
                font.family: Theme.fam(text, Theme.families)
                font.features: { "tnum": 1 }
            }
        }
    }
}
