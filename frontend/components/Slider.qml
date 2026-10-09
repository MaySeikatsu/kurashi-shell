import QtQuick
import "../core"

// Optimistic slider: follows the pointer locally while dragging, sends at most one intent per
// frame (and only while the pointer is held, Ma), and shows the daemon value otherwise.
// Keyboard: Tab focuses it; Left/Down and Right/Up step by `step`, PageUp/PageDown by 10 %, Home
// and End go to the ends. A key press is an event, so each press sends one intent. The knob keeps
// showing the daemon value until it answers, so only values in effect are shown (Shōjiki).
// `unavailable`: there is no level to show (the caller says why). Then no track, fill or knob is
// drawn, only a dim "⊘", and the control takes no pointer, key or Tab input (B2).
Item {
    id: s
    property real value: 0              // daemon value
    property color track: Theme.outline
    property color fill: Theme.accent
    property string a11y: ""            // translated accessible name, from the caller
    property real step: 0.05
    property bool unavailable: false
    signal moved(real v)

    property bool dragging: false
    property real local: 0
    property bool dirty: false
    // A key target the daemon has not confirmed yet; repeated keys build on it.
    property bool keyPending: false
    property real keyTarget: 0
    // Clamped (B12): a level past the scale, such as svc.audio's 1.5, must not draw past the track.
    readonly property real shown: Math.max(0, Math.min(1, dragging ? local : value))

    implicitWidth: 120
    implicitHeight: 20
    activeFocusOnTab: !s.unavailable

    onValueChanged: if (keyPending && Math.abs(value - keyTarget) < 0.005) keyPending = false
    // Input in flight when the level goes away gets no release and no answer: drop it.
    onUnavailableChanged: if (unavailable) { dragging = false; dirty = false; keyPending = false }

    function setKey(v) {
        keyTarget = Math.max(0, Math.min(1, v)); keyPending = true; s.moved(keyTarget)
    }
    function nudge(d) { setKey((keyPending ? keyTarget : value) + d) }

    Keys.enabled: !s.unavailable
    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Left: case Qt.Key_Down: s.nudge(-s.step); break
        case Qt.Key_Right: case Qt.Key_Up: s.nudge(s.step); break
        case Qt.Key_PageDown: s.nudge(-0.1); break
        case Qt.Key_PageUp: s.nudge(0.1); break
        case Qt.Key_Home: s.setKey(0); break
        case Qt.Key_End: s.setKey(1); break
        default: return
        }
        event.accepted = true
    }
    Accessible.role: Accessible.Slider
    Accessible.name: s.a11y

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3; color: s.track
        visible: !s.unavailable
        Rectangle { width: parent.width * s.shown; height: parent.height; radius: 3; color: s.fill }
    }
    Rectangle {
        width: 12; height: 12; radius: 6; color: s.fill
        anchors.verticalCenter: parent.verticalCenter
        x: (s.width - width) * s.shown
        visible: !s.unavailable
    }
    // Stands in for the level (VolumeFace draws the same mark for no audio). Dim: it is not an input.
    Text {
        anchors.centerIn: parent
        visible: s.unavailable
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: "⊘"
    }
    FrameAnimation {
        running: s.dragging
        onTriggered: if (s.dirty) { s.dirty = false; s.moved(s.local) }
    }
    function setFrom(x) {
        local = Math.max(0, Math.min(1, x / width)); dirty = true
    }
    MouseArea {
        anchors.fill: parent
        // The hit area grows to the control height; the drawn track keeps its size.
        anchors.topMargin: -Math.max(0, (Theme.controlH - s.height) / 2)
        anchors.bottomMargin: -Math.max(0, (Theme.controlH - s.height) / 2)
        enabled: !s.unavailable
        onPressed: m => { s.dragging = true; s.setFrom(m.x) }
        onPositionChanged: m => { if (s.dragging) s.setFrom(m.x) }
        onReleased: { s.dragging = false; s.moved(s.local); s.dirty = false }
        onCanceled: { s.dragging = false; s.dirty = false }
    }
    FocusRing {
        anchors.fill: parent
        shown: s.activeFocus
        corner: Theme.rSm
    }
}
