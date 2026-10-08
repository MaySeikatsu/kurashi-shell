import QtQuick

Item {
    id: s
    property real value: 0              // daemon value
    property color track
    property color fill
    signal moved(real v)                // emitted at most once per frame while dragging

    property bool dragging: false
    property real local: 0
    property bool dirty: false
    readonly property real shown: dragging ? local : value

    implicitWidth: 120
    implicitHeight: 20

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 6; radius: 3; color: s.track
        Rectangle { width: parent.width * s.shown; height: parent.height; radius: 3; color: s.fill }
    }
    Rectangle {
        width: 12; height: 12; radius: 6; color: s.fill
        anchors.verticalCenter: parent.verticalCenter
        x: (s.width - width) * s.shown
    }
    // Frame-paced sender: only runs while the pointer is held.
    FrameAnimation {
        running: s.dragging
        onTriggered: if (s.dirty) { s.dirty = false; s.moved(s.local) }
    }
    function setFrom(x) {
        local = Math.max(0, Math.min(1, x / width)); dirty = true
    }
    MouseArea {
        anchors.fill: parent
        onPressed: m => { s.dragging = true; s.setFrom(m.x) }
        onPositionChanged: m => { if (s.dragging) s.setFrom(m.x) }
        onReleased: { s.dragging = false; s.moved(s.local); s.dirty = false }
        onCanceled: { s.dragging = false; s.dirty = false }
    }
}
