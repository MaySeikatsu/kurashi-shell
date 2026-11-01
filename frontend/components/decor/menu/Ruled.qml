import QtQuick
import QtQuick.Shapes
import "../../../core"

// Ruled (W53.7, docs/ux/styles.md §9 washi): a menu as a sheet of ruled washi — every row stands on a hairline rule
// (罫線, the ink at a fifth of its strength, a little in from both sides, as a printed rule stops short of the paper's
// edge), the chosen row is an ink wash (薄墨: the sumi's ink thinning from the row's start to nothing at its end, as a
// wide brush runs dry) with one short tapered beni stroke at its start, where a reader's brush would mark a line. A
// separator is the rule doubled (二重罫). Roles only (rule 4); static.
MenuRowBase {
    id: row
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property real inset: 6

    // The rule under every row (and twice for a separator).
    Rectangle {
        visible: !row.separator
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: row.inset; rightMargin: row.inset }
        height: row.hair
        color: Qt.alpha(Theme.fg, 0.2)
    }
    Item {
        visible: row.separator
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: row.inset; rightMargin: row.inset }
        height: 3 * row.hair
        Rectangle { width: parent.width; height: row.hair; color: Qt.alpha(Theme.fg, 0.32) }
        Rectangle { y: 2 * row.hair; width: parent.width; height: row.hair; color: Qt.alpha(Theme.fg, 0.32) }
    }

    // The chosen row: the wash, then the mark (made only on that row).
    Loader {
        anchors.fill: parent
        anchors.bottomMargin: row.hair
        active: row.highlighted && row.enabled && !row.separator
        sourceComponent: Item {
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.fg, 0.13) }
                    GradientStop { position: 0.55; color: Qt.alpha(Theme.fg, 0.07) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.fg, 0.0) }
                }
            }
            // A short upright stroke, thick at its middle, thinning to both ends.
            Shape {
                id: mk
                x: 5
                width: 4
                height: parent.height
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: Theme.accent
                    startX: 2; startY: 9
                    PathCubic { x: 2.3; y: mk.height - 8; control1X: 4.0; control1Y: 15; control2X: 3.8; control2Y: mk.height - 15 }
                    PathCubic { x: 2; y: 9; control1X: 0.4; control1Y: mk.height - 16; control2X: 0.6; control2Y: 16 }
                }
            }
        }
    }
}
