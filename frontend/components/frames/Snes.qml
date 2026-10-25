import QtQuick
import "../../core"

// SNES (decor snes; shellseikatsu `Widgets/ThemeDecor/SnesFrame.qml`, `Panels/Lockscreen/LockStyleSnes.qml`). Cards:
// the console's hard plastic seams (a double border), the logo's four dots top-left and the two purple buttons
// top-right. Small blocks: nothing (the keycap chrome is the console's buttons). Ground: the logo dots large above the
// column and the purple slide switches below it. Dots: secondary (red), tertiary (yellow), success (green), accent.
// W42: each part is a Loader, so a block of the other kind builds none of it. A `visible` tree was made for every block
// (a small one built ~30 hidden items, ~0.75 ms, for nothing drawn); the drawing is the same, in the same order.
FrameBase {
    id: f
    readonly property var dots: [Theme.secondary, Theme.color("color.warning", "#e8a818"),
                                 Theme.color("color.success", "#3a9e48"), Theme.color("color.data.1", "#2e5fb8")]
    readonly property color purple: Theme.accent

    component Dots: Row {
        id: dr
        property real size: 6
        spacing: size / 2
        Repeater {
            model: f.dots
            Rectangle { required property color modelData; width: dr.size; height: dr.size; color: modelData }
        }
    }
    component Pill: Rectangle {
        width: 14; height: 7
        radius: height / 2
        color: f.purple
        border.width: 1
        border.color: Qt.darker(f.purple, 1.6)
    }

    Loader {
        active: f.card
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            Rectangle {
                anchors { fill: parent; margins: 4 }
                color: "transparent"
                border.width: 2
                border.color: Theme.outline
                opacity: 0.6
            }
            Rectangle {
                anchors { fill: parent; margins: 7 }
                color: "transparent"
                border.width: 1
                border.color: Theme.color("color.outline_variant", "#90918c")
                opacity: 0.8
            }
            Dots { x: 12; y: 10 }
            Row {
                anchors { right: parent.right; top: parent.top; rightMargin: 12; topMargin: 9 }
                spacing: 4
                Pill {}
                Pill {}
            }
        }
    }

    // ---- ground ----
    Loader {
        active: f.ground
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.lighter(Theme.surface, 1.06) }
                    GradientStop { position: 1.0; color: Qt.darker(Theme.surface, 1.08) }
                }
            }
            // The cartridge slot.
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.08 }
                width: Math.min(parent.width * 0.5, 640)
                height: 18
                color: Qt.darker(Theme.surface, 1.35)
                border.width: 2
                border.color: Theme.line
            }
            Dots {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.verticalCenter; bottomMargin: 230 }
                size: 18
            }
            Row {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: 220 }
                spacing: 18
                Pill { width: 56; height: 22 }
                Pill { width: 56; height: 22 }
            }
        }
    }
}
