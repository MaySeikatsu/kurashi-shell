import QtQuick
import "../../core"

// A level as a thick rounded bar whose fill follows the level on a spring (W21, the OSD of Apple's island and Capsule's
// satellites): it fills from empty when it appears and springs to each new level, so a volume key press reads as motion.
// The spring runs only while the level moves and `animate` (the face is live); Theme.springOn false snaps.
Item {
    id: lm
    property real level: 0
    property color color: Theme.accent
    property color track: Qt.alpha(Theme.fg, 0.14)
    property bool animate: false
    property real thickness: 6
    implicitWidth: 90
    implicitHeight: thickness
    // Starts empty and takes the level after the first layout, so the fill grows in.
    property real shown: 0
    Component.onCompleted: Qt.callLater(function () { lm.shown = Qt.binding(function () { return Math.max(0, Math.min(1, lm.level)) }) })
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: lm.track
    }
    Rectangle {
        id: bar
        height: parent.height
        radius: height / 2
        color: lm.color
        width: lm.shown > 0 ? Math.max(height, parent.width * lm.shown) : 0
        Behavior on width {
            enabled: lm.animate && Theme.springOn
            SpringAnimation { spring: Theme.spring * 1.4; damping: Math.min(1, Theme.damping + 0.1); epsilon: 0.25 }
        }
    }
}
