import QtQuick
import "../../../core"
import ".."

// Classic (W53.1): a bevel-era check box — a 13 × 13 sunken field (shadow then black at the top left, highlight then light
// at the bottom right), white, grey while pressed, with the 7 × 7 tick on whole pixels when checked; at the start of the
// toggle, centred on its height. Static.
ToggleBase {
    id: tg
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    implicitWidth: 13
    implicitHeight: 13
    Item {
        id: box
        width: 13
        height: 13
        y: Math.round((tg.height - height) / 2)
        Rectangle {
            anchors.fill: parent
            color: tg.pressed ? Theme.surface : Theme.color("color.surface_container_lowest", "#ffffff")
        }
        BevelEdge {
            anchors.fill: parent
            w: tg.hair
            sunk: true
            dark: Theme.bevelDark2
            dark2: Theme.bevelDark
        }
        // The tick: a 7 × 7 check, three pixels thick, rows from the left.
        Repeater {
            model: tg.checked ? [[3, 5, 3], [4, 6, 3], [5, 7, 3], [6, 6, 3], [7, 5, 3], [8, 4, 3], [9, 3, 3]] : []
            Rectangle {
                required property var modelData
                x: modelData[0]; y: modelData[1]
                width: 1; height: modelData[2]
                color: Theme.fg
            }
        }
    }
}
