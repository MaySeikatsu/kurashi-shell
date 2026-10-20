import QtQuick
import "../../core"

// Liquid-glass highlight (decor aqua; shellseikatsu `Widgets/GlassSheen.qml`): a specular rim all round, a top
// hairline inset past the corner curve, and a faint sheen wash over the upper quarter. Static. No ground of its own:
// the lock keeps the soft chrome's glows.
FrameBase {
    id: f
    grounds: false
    // How bright the glass catches light: less on small things inside other blocks.
    readonly property real amount: f.small ? 0.6 : 1
    readonly property real r: Math.max(0, f.radius)

    Rectangle {
        visible: !f.ground
        anchors.fill: parent
        radius: f.r
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16 * f.amount)
    }
    Rectangle {
        visible: !f.ground
        anchors { top: parent.top; topMargin: 1; left: parent.left; right: parent.right
                  leftMargin: Math.max(2, f.r * 0.6); rightMargin: Math.max(2, f.r * 0.6) }
        height: 1
        color: Qt.rgba(1, 1, 1, 0.32 * f.amount)
    }
    Rectangle {
        visible: !f.ground
        anchors { top: parent.top; topMargin: 1; left: parent.left; right: parent.right
                  leftMargin: f.r; rightMargin: f.r }
        height: Math.max(8, parent.height * 0.25)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08 * f.amount) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
}
