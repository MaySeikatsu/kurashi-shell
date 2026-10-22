import QtQuick
import "../core"

// Slider. While dragging only the shown number moves; the value goes out once, on release (`committed`), so one drag
// is one change. Arrow keys move one step (`previewed`, so a previewable row can show it first); Return commits what
// is shown, Escape is `cancelled`.
Item {
    id: s
    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0
    property bool integer: false
    property string unit: ""
    property bool enabled: true
    property string label: ""
    signal committed(real value)
    signal previewed(real value)
    signal cancelled()
    // Escape is taken only while there is something to take back (the row binds its open preview); otherwise it goes on
    // up, where the sheet closes on it (K63).
    property bool cancellable: true

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
    implicitHeight: Theme.controlH
    activeFocusOnTab: s.enabled
    Accessible.role: Accessible.Slider
    Accessible.name: s.label
    Accessible.description: readout.text

    function snap(v) {
        v = Math.max(from, Math.min(to, v))
        if (step > 0) v = from + Math.round((v - from) / step) * step
        if (integer) v = Math.round(v)
        return Number(v.toFixed(decimals))
    }
    function at(x) { return snap(from + Math.max(0, Math.min(1, x / track.width)) * (to - from)) }
    // One step per arrow key, from the value shown. Without a step: a hundredth of the range (never less than 1 for an
    // integer setting, so a key always moves it).
    function nudge(d) {
        if (!s.enabled) return
        var st = step > 0 ? step : Math.max(integer ? 1 : 0, (to - from) / 100)
        var v = snap(shown + d * st)
        if (v !== shown) s.previewed(v)
    }

    Keys.onPressed: event => {
        var d = 0
        switch (event.key) {
        case Qt.Key_Left: case Qt.Key_Down: d = -1; break
        case Qt.Key_Right: case Qt.Key_Up: d = 1; break
        case Qt.Key_Return: case Qt.Key_Enter: s.committed(s.shown); event.accepted = true; return
        case Qt.Key_Escape: if (s.cancellable || s.dragging) { s.cancelled(); event.accepted = true }; return
        default: return
        }
        s.nudge(d)
        event.accepted = true
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: readout.left
        anchors.rightMargin: Theme.gap
        height: 4
        radius: 2
        color: Theme.containerHigh
        opacity: s.enabled ? 1 : 0.5
        Rectangle {
            width: parent.width * (s.to > s.from ? (s.shown - s.from) / (s.to - s.from) : 0)
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
        id: readout
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 72
        horizontalAlignment: Text.AlignRight
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: s.shown.toFixed(s.decimals) + (s.unit ? " " + s.unit : "")
    }
    MouseArea {
        // The track is 4 px tall; the hit area spans the control height and 6 px past both ends.
        anchors.left: track.left
        anchors.right: track.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: -6
        anchors.rightMargin: -6
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
    FocusRing {
        anchors.fill: parent
        shown: s.activeFocus
        corner: 4
    }
}
