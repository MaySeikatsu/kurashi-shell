import QtQuick
import "../../core"

// Win9x outset bevel (decor win95; shellseikatsu `Widgets/BevelBorder.qml`, `Panels/Lockscreen/LockStyleRetro.qml`):
// two 1 px frames — outer light top/left and dark bottom/right, inner lighter top/left and mid grey bottom/right —
// sunken (inverted) while pressed. Colours from roles: `ring` (highlight), the highest container, `outline` (shade),
// `line` (dark edge). Ground: the teal desktop (secondary) with a silver logon window behind the lock's column.
FrameBase {
    id: f
    readonly property color hi: f.pressed ? Theme.line : Theme.ring
    readonly property color hi2: f.pressed ? Theme.outline : Theme.color("color.surface_container_highest", "#dfdfdf")
    readonly property color lo2: f.pressed ? Theme.color("color.surface_container_highest", "#dfdfdf") : Theme.outline
    readonly property color lo: f.pressed ? Theme.ring : Theme.line

    component Bevel: Item {
        id: bv
        property color a: f.hi
        property color a2: f.hi2
        property color b2: f.lo2
        property color b: f.lo
        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 1; color: bv.a }
        Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom } width: 1; color: bv.a }
        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 1; color: bv.b }
        Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom } width: 1; color: bv.b }
        Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 } height: 1; color: bv.a2 }
        Rectangle { anchors { top: parent.top; left: parent.left; bottom: parent.bottom; margins: 1 } width: 1; color: bv.a2 }
        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 1 } height: 1; color: bv.b2 }
        Rectangle { anchors { top: parent.top; right: parent.right; bottom: parent.bottom; margins: 1 } width: 1; color: bv.b2 }
    }

    Bevel { anchors.fill: parent; visible: !f.ground }

    // ---- ground: teal desktop, a silver logon window (navy title band) behind the lock's column ----
    Rectangle { visible: f.ground; anchors.fill: parent; color: Theme.secondary }
    Rectangle {
        id: win
        visible: f.ground
        anchors.centerIn: parent
        width: 470
        height: 400
        color: Theme.container
        Bevel { anchors.fill: parent; a: Theme.color("color.surface_container_highest", "#dfdfdf"); a2: Theme.ring }
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 3 }
            height: 20
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Qt.lighter(Theme.accent, 2.2) }
            }
            // The three title buttons.
            Row {
                anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
                spacing: 2
                Repeater {
                    model: 3
                    Rectangle {
                        width: 16; height: 14
                        color: Theme.container
                        Bevel { anchors.fill: parent }
                    }
                }
            }
        }
    }
}
