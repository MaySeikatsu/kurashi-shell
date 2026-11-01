import QtQuick
import "../../core"

// SNES (W53.5, docs/ux/styles.md §7): every block a 16-bit RPG window, on the output's pixel grid (`Theme.grid`, one grid
// pixel = 2 px on 1080 lines; whole device px at scale 1.5 too). Cards: a dark outline one grid pixel wide (`line`), a
// white border two grid pixels wide inside it (`ring`), both with the look's small radius drawn without antialiasing — a
// stepped corner, as the pixel art has it — over the block's banded fill (Block, `[decor] fill.bands`). Small blocks (keys,
// tiles, the island's text box): the outline and a border one grid pixel wide. Ground (the plain lock face under this
// look): the screen's black with the controller's four face colours as a diamond of pixel dots (X blue on top, A red at
// the right, B yellow below, Y green at the left). Colours are roles (rule 4); static (one paint per size and colour).
FrameBase {
    id: f
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    readonly property color dark: Theme.color("color.line", "#000000")
    readonly property color white: Theme.color("color.ring", "#f8f8f8")
    readonly property int border: card ? 2 * g : g

    Loader {
        active: !f.ground
        anchors.fill: parent
        sourceComponent: Item {
            Rectangle {
                anchors.fill: parent
                radius: f.radius
                antialiasing: false
                color: "transparent"
                border.width: f.g
                border.color: f.dark
            }
            Rectangle {
                anchors { fill: parent; margins: f.g }
                radius: Math.max(0, f.radius - f.g)
                antialiasing: false
                color: "transparent"
                border.width: f.border
                border.color: f.white
            }
        }
    }

    // ---- ground ----
    Loader {
        active: f.ground
        anchors.fill: parent
        sourceComponent: Item {
            Rectangle { anchors.fill: parent; color: Theme.surface }
            Item {
                id: cluster
                readonly property int d: 6 * f.g
                width: 3 * d; height: 3 * d
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.verticalCenter; bottomMargin: 120 }
                Repeater {
                    model: [[1, 0, "color.tertiary"], [2, 1, "color.secondary"], [1, 2, "color.warning"], [0, 1, "color.success"]]
                    Rectangle {
                        required property var modelData
                        x: modelData[0] * cluster.d; y: modelData[1] * cluster.d
                        width: cluster.d; height: cluster.d
                        radius: f.g
                        antialiasing: false
                        color: Theme.color(modelData[2], "#ffffff")
                    }
                }
            }
        }
    }
}
