import QtQuick
import "../../../core"

// Line (session 28): the plain slider, refined. A 6 px rail, the level in the accent, a round knob that carries a dot
// of the ground while it rests and opens into a ring when hovered or held, with a soft halo under the hand. Static at
// rest; the knob's changes ease on the fast curve.
SliderBase {
    id: sl
    property bool hovered: false
    readonly property real v: Math.max(0, Math.min(1, value))
    readonly property real len: vertical ? height : width
    readonly property real thick: vertical ? width : height
    readonly property real knob: Math.min(16, thick)
    readonly property real at: (len - knob) * v
    Item {
        id: body
        width: sl.len; height: sl.thick
        anchors.centerIn: parent
        rotation: sl.vertical ? -90 : 0
        Rectangle {
            y: Math.round((body.height - height) / 2)
            width: body.width; height: 6; radius: Math.min(3, Theme.rFull)
            color: Theme.selected
        }
        Rectangle {
            y: Math.round((body.height - height) / 2)
            width: sl.at + sl.knob / 2; height: 6; radius: Math.min(3, Theme.rFull)
            color: Theme.accent
        }
        // The stop at the rail's end: where full is.
        Rectangle {
            visible: sl.v < 0.94
            x: body.width - 5; y: Math.round((body.height - 2) / 2)
            width: 2; height: 2; radius: 1
            color: Theme.dim
        }
        Rectangle {
            x: sl.at + sl.knob / 2 - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: sl.pressed ? 30 : (sl.hovered ? 24 : sl.knob); height: width; radius: Math.min(width / 2, Theme.rFull)
            color: Qt.alpha(Theme.accent, sl.pressed ? 0.22 : (sl.hovered ? 0.14 : 0))
            Behavior on width { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            x: sl.at
            anchors.verticalCenter: parent.verticalCenter
            width: sl.knob; height: sl.knob; radius: Math.min(sl.knob / 2, Theme.rFull)
            color: Theme.accent
            Rectangle {
                anchors.centerIn: parent
                width: sl.pressed ? 4 : (sl.hovered ? 8 : 6); height: width; radius: Math.min(width / 2, Theme.rFull)
                color: Theme.fgOnAccent
                Behavior on width { enabled: Theme.timed; NumberAnimation { duration: Theme.fastMs; easing.type: Easing.OutCubic } }
            }
        }
    }
}
