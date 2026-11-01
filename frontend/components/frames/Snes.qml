import QtQuick
import "../../core"

// SNES (W53.5, docs/ux/styles.md §7): every block a 16-bit RPG window, on the output's pixel grid (`Theme.grid`, one grid
// pixel = 2 px on 1080 lines; whole device px at scale 1.5 too). Cards: Final Fantasy VI's dialogue frame as measured on a
// native capture (vgmuseum.com/end/snes/a/ff3w-004.gif: white #f8f8f8, light grey #b8b8b8, dark grey #606868 from the
// outside in, one pixel each) inside a dark outline one grid pixel wide (Dragon Quest VI's, the brief's), each ring with
// the look's small radius drawn without antialiasing — a stepped corner, as the pixel art has it — over the block's banded
// fill (Block, `[decor] fill.bands`). Small blocks (keys, tiles, the island's text box): the outline and the white ring.
// Ground (the plain lock face under this look): the screen's black with the pad's four face colours as a diamond of pixel
// dots (X blue on top, A red at the right, B yellow below, Y green at the left). Colours are roles (rule 4); static.
FrameBase {
    id: f
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    readonly property var rings: card
        ? [Theme.color("color.line", "#000000"), Theme.color("color.ring", "#f8f8f8"),
           Theme.color("color.outline", "#b8b8b8"), Theme.color("color.outline_variant", "#606868")]
        : [Theme.color("color.line", "#000000"), Theme.color("color.ring", "#f8f8f8")]

    Loader {
        active: !f.ground
        anchors.fill: parent
        sourceComponent: Item {
            Repeater {
                model: f.rings
                Rectangle {
                    required property int index
                    required property color modelData
                    anchors { fill: parent; margins: index * f.g }
                    radius: Math.max(0, f.radius - index * f.g)
                    antialiasing: false
                    color: "transparent"
                    border.width: f.g
                    border.color: modelData
                }
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
