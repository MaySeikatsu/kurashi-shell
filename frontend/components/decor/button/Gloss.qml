import QtQuick
import "../../../core"

// Gloss (W53.2): a glossy push button — Windows XP's (docs/ux/styles.md §2, measured on guidebookgallery.org's
// pics/gui/desktop/full/winxppro.png, the "Connect" button x 210–284, y 483–505): 3 px corners, a 1 px rim in the deep
// blue of the accent, a white face falling to the window face at its foot; hovered (and the default button at rest in
// XP's focus colours) an inner glow two px deep — the tertiary role's orange top and foot (XP's #fdd889 / #f8b330) on
// hover, the accent's pale blue on the default; pressed, the face darkens and loses its light. The caller's content
// sits on it. Static (one paint per state).
ButtonBase {
    id: bf
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property color face: Theme.surface
    readonly property bool glowOn: hovered || primary
    readonly property color glow: hovered ? Theme.tertiary : Qt.lighter(Theme.accent, 1.6)
    Rectangle {
        anchors.fill: parent
        radius: 3
        color: Qt.darker(Theme.accent, 2.2)
    }
    Rectangle {
        anchors { fill: parent; margins: bf.hair }
        radius: 2
        gradient: Gradient {
            GradientStop { position: 0; color: bf.pressed || bf.checked ? Qt.darker(bf.face, 1.12) : Qt.lighter(bf.face, 1.12) }
            GradientStop { position: 0.85; color: bf.pressed || bf.checked ? Qt.darker(bf.face, 1.05) : Qt.tint(bf.face, Qt.rgba(1, 1, 1, 0.5)) }
            GradientStop { position: 1; color: bf.pressed || bf.checked ? bf.face : Qt.darker(bf.face, 1.08) }
        }
    }
    // The inner glow: two px along the top and the foot, one along the sides.
    Item {
        visible: bf.glowOn && !bf.pressed
        anchors { fill: parent; margins: bf.hair }
        Rectangle { x: 1; y: 0; width: parent.width - 2; height: 1; color: Qt.lighter(bf.glow, 1.3) }
        Rectangle { x: 1; y: 1; width: parent.width - 2; height: 1; color: Qt.lighter(bf.glow, 1.12) }
        Rectangle { x: 1; y: parent.height - 2; width: parent.width - 2; height: 1; color: bf.glow }
        Rectangle { x: 1; y: parent.height - 1; width: parent.width - 2; height: 1; color: Qt.darker(bf.glow, 1.1) }
        Rectangle { x: 0; y: 1; width: 1; height: parent.height - 2; color: Qt.alpha(bf.glow, 0.7) }
        Rectangle { x: parent.width - 1; y: 1; width: 1; height: parent.height - 2; color: Qt.alpha(bf.glow, 0.7) }
    }
}
