import QtQuick
import "../../../core"

// Glow (W53.5, docs/ux/styles.md §8): a PS2 dashboard row — the selected row lit by a soft band of tower blue that is
// brightest at the row's start and fades out toward its end, over a hairline of the same light along its foot; the rest
// of the rows stand on the void. A separator is a gap. High contrast (no glow): a solid outline round the row instead.
// Roles only (rule 4); static.
MenuRowBase {
    id: row
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool lit: row.highlighted && row.enabled && !row.separator
    Rectangle {
        visible: row.lit && Theme.glow > 0
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.alpha(Theme.accent, 0.34) }
            GradientStop { position: 0.55; color: Qt.alpha(Theme.accent, 0.14) }
            GradientStop { position: 1.0; color: Qt.alpha(Theme.accent, 0) }
        }
    }
    Rectangle {
        visible: row.lit && Theme.glow > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: row.hair
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.lighter(Theme.accent, 1.3) }
            GradientStop { position: 0.7; color: Qt.alpha(Theme.accent, 0.4) }
            GradientStop { position: 1.0; color: Qt.alpha(Theme.accent, 0) }
        }
    }
    Rectangle {
        visible: row.lit && Theme.glow <= 0
        anchors.fill: parent
        color: "transparent"
        border.width: row.hair
        border.color: Theme.fg
    }
}
