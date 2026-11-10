import QtQuick
import "../../../core"

// Capsule (session 28): the level is the fill of one thick capsule, no knob — a grip line stands at the fill's end and
// shows under the hand. The capsule swells a little while held. Static at rest.
SliderBase {
    id: sl
    property bool hovered: false
    readonly property real v: Math.max(0, Math.min(1, value))
    readonly property real len: vertical ? height : width
    readonly property real thick: vertical ? width : height
    readonly property real h: Math.min(thick, sl.pressed ? 20 : 16)
    Item {
        id: body
        width: sl.len; height: sl.thick
        anchors.centerIn: parent
        rotation: sl.vertical ? -90 : 0
        Rectangle {
            id: rail
            anchors.verticalCenter: parent.verticalCenter
            width: body.width; height: sl.h; radius: Math.min(height / 2, Theme.rFull)
            color: Theme.selected
            clip: true
            Behavior on height { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
            Rectangle {
                width: Math.max(rail.height, rail.width * sl.v); height: rail.height; radius: rail.radius
                visible: sl.v > 0
                color: Theme.accent
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: Math.max(4, rail.height / 2 - 1)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2; height: Math.max(4, rail.height - 8); radius: 1
                    color: Theme.fgOnAccent
                    opacity: sl.pressed ? 0.95 : (sl.hovered ? 0.7 : 0.35)
                    visible: parent.width > rail.height + 4
                }
            }
        }
    }
}
