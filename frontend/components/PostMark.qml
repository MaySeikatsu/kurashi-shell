import QtQuick
import "../core"

// I471c (K118): what holds a posted card on the desktop: a pin through its top middle, or two strips of tape over its top
// corners. Drawn over the card, static (a Canvas-free stack of rectangles: nothing repaints at rest). `kind`: "pin" or
// "tape". The pin's head is the accent with a highlight and a small shadow on the card; tape is a translucent strip in a
// paper tone, a little rough at its torn ends.
Item {
    id: pm
    property string kind: "pin"
    // A card's own seed (its id's hash), so no two strips of tape lie alike.
    property int seed: 0
    readonly property color tapeTone: Qt.rgba(Theme.fg.r * 0.25 + 0.72, Theme.fg.g * 0.25 + 0.68, Theme.fg.b * 0.25 + 0.55, 0.62)

    // ---- the pin ----
    Item {
        visible: pm.kind === "pin"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        width: 16
        height: 16
        // its shadow on the card, away from the light (down and right)
        Rectangle { x: 4; y: 5; width: 14; height: 14; radius: 7; color: Qt.rgba(0, 0, 0, 0.28) }
        Rectangle {
            id: head
            width: 14; height: 14; radius: 7
            color: Theme.accent
            border.width: 1
            border.color: Qt.darker(Theme.accent, 1.5)
        }
        Rectangle { x: 3; y: 3; width: 4; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.75) }
    }

    // ---- the tape: one strip over each top corner, turned across the corner ----
    Repeater {
        model: pm.kind === "tape" ? 2 : 0
        delegate: Item {
            required property int index
            readonly property real turn: (index === 0 ? -38 : 38) + ((pm.seed >> (index * 3)) % 9) - 4
            x: index === 0 ? -14 : pm.width - width + 14
            y: -6
            width: 58
            height: 20
            rotation: turn
            Rectangle {
                anchors.fill: parent
                color: pm.tapeTone
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.10)
            }
            // the torn ends: three teeth cut out of each end by the ground's tone would need the ground; a lighter sliver
            // at each end reads as the tape's cut edge instead
            Rectangle { width: 2; height: parent.height; color: Qt.rgba(1, 1, 1, 0.35) }
            Rectangle { x: parent.width - 2; width: 2; height: parent.height; color: Qt.rgba(1, 1, 1, 0.35) }
        }
    }
}
