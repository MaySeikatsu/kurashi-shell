import QtQuick
import "../../../core"

// Glow (W53.5, docs/ux/styles.md §8): a PS2 dashboard tooltip — the void's dark glass (`[decor] tooltip.fill`), a silver
// hairline round it and a line of tower blue along its foot that fades toward both ends. High contrast: the hairline
// alone, solid. Roles only (rule 4); static.
TooltipBase {
    id: tt
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property string fill: Theme.decor("tooltip.fill", "")
    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: Qt.alpha(tt.fill !== "" ? tt.fill : Theme.color("color.surface_container_lowest", "#040609"), 0.92)
        border.width: tt.hair
        border.color: Qt.alpha(Theme.fg, Theme.glow > 0 ? 0.28 : 1)
    }
    Rectangle {
        visible: Theme.glow > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: Theme.rSm; rightMargin: Theme.rSm; bottomMargin: tt.hair }
        height: tt.hair
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Theme.accent }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
