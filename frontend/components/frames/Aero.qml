import QtQuick
import "../../core"

// Windows 7 "Aero" (decor aero; shellseikatsu `Widgets/GlassSheen.qml`, `Widgets/SurfaceFrame.qml`,
// `Panels/Lockscreen/LockStyleWin7.qml`). Every block: the glass sheen (rim, top hairline, upper wash). Cards also sit
// in a tinted glass window band. Ground: a light aero field with a soft bloom and faint diagonal aurora beams.
FrameBase {
    id: f
    readonly property real r: Math.max(0, f.radius)
    readonly property color glass: Qt.lighter(Theme.accent, 1.6)

    Sheen {
        anchors.fill: parent
        visible: !f.ground
        radius: f.radius
        kind: f.kind
    }
    // The window band: translucent tinted glass round a card, with a white inner edge.
    Rectangle {
        visible: f.card
        anchors.fill: parent
        radius: f.r
        color: "transparent"
        border.width: 5
        border.color: Qt.alpha(f.glass, 0.45)
    }
    Rectangle {
        visible: f.card
        anchors { fill: parent; margins: 5 }
        radius: Math.max(0, f.r - 5)
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.55)
    }

    // ---- ground ----
    Item {
        visible: f.ground
        anchors.fill: parent
        clip: true
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(Theme.surface, 1.04) }
                GradientStop { position: 0.6; color: Theme.surface }
                GradientStop { position: 1.0; color: Qt.tint(Theme.surface, Qt.alpha(Theme.accent, 0.3)) }
            }
        }
        Glow {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height * 0.06
            width: parent.width * 0.75
            height: parent.height * 0.8
            color: "#ffffff"
            alpha: 0.45
        }
        Rectangle { x: -parent.width * 0.1; y: parent.height * 0.25; width: parent.width * 1.2; height: 2
                    rotation: -18; color: "#ffffff"; opacity: 0.4 }
        Rectangle { x: -parent.width * 0.1; y: parent.height * 0.55; width: parent.width * 1.2; height: 3
                    rotation: -14; color: f.glass; opacity: 0.35 }
    }
}
