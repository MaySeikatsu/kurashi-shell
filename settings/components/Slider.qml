import QtQuick
import "../core"

// Slider with local preview: while dragging only the shown number moves; the value goes out once,
// on release (`committed`), so one interaction = one apply transaction.
Item {
    id: s
    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0
    property bool integer: false
    property string unit: ""
    property bool enabled: true
    signal committed(real value)

    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: dragging ? dragValue : value
    readonly property int decimals: {
        if (integer || step <= 0) return integer ? 0 : 2
        var d = 0
        while (d < 6 && Math.abs(step * Math.pow(10, d) - Math.round(step * Math.pow(10, d))) > 1e-9) d++
        return d
    }

    implicitWidth: 260
    implicitHeight: 24

    function snap(v) {
        v = Math.max(from, Math.min(to, v))
        if (step > 0) v = from + Math.round((v - from) / step) * step
        if (integer) v = Math.round(v)
        return Number(v.toFixed(decimals))
    }
    function at(x) { return snap(from + Math.max(0, Math.min(1, x / track.width)) * (to - from)) }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: label.left
        anchors.rightMargin: Theme.gap
        height: 4
        radius: 2
        color: Theme.containerHigh
        opacity: s.enabled ? 1 : 0.5
        Rectangle {
            width: parent.width * (to > from ? (s.shown - s.from) / (s.to - s.from) : 0)
            height: parent.height
            radius: 2
            color: Theme.accent
        }
        Rectangle {
            width: 14
            height: 14
            radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * (s.to > s.from ? (s.shown - s.from) / (s.to - s.from) : 0) - width / 2
            color: Theme.fg
        }
    }
    Text {
        id: label
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 64
        horizontalAlignment: Text.AlignRight
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: s.shown.toFixed(s.decimals) + (s.unit ? " " + s.unit : "")
    }
    MouseArea {
        anchors.fill: track
        anchors.margins: -6
        enabled: s.enabled
        onPressed: mouse => { s.dragging = true; s.dragValue = s.at(mouse.x - 6) }
        onPositionChanged: mouse => { if (pressed) s.dragValue = s.at(mouse.x - 6) }
        onReleased: {
            var v = s.dragValue
            s.dragging = false
            if (v !== s.value) s.committed(v)
        }
        onCanceled: s.dragging = false
    }
}
