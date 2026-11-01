import QtQuick
import "../../../core"

// Void (W53.5, docs/ux/styles.md §8): the bar as a thin strip of the PS2 dashboard's void — the panel's dark glass at the
// look's opacity, a silver hairline along the side facing the screen's middle and, just inside it, a line of tower blue
// that fades out toward both ends (the dashboard's glow lines). The labels on it glow through the look's
// `material.glow`. Roles only (rule 4); static.
BarBase {
    id: v
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool lineAtTop: inner === "top"
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.color("color.surface_container_lowest", "#040609"), Theme.panel.a)
    }
    Rectangle {
        visible: !v.vertical
        anchors { left: parent.left; right: parent.right }
        y: v.lineAtTop ? 0 : parent.height - height
        height: v.hair
        color: Qt.alpha(Theme.fg, 0.32)
    }
    Rectangle {
        visible: !v.vertical
        anchors { left: parent.left; right: parent.right }
        y: v.lineAtTop ? v.hair : parent.height - 2 * v.hair
        height: v.hair
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(Theme.accent, 0.9) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    Rectangle {
        visible: v.vertical
        anchors { top: parent.top; bottom: parent.bottom }
        x: v.inner === "left" ? 0 : parent.width - width
        width: v.hair
        color: Qt.alpha(Theme.fg, 0.32)
    }
}
