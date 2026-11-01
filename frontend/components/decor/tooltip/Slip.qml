import QtQuick
import "../../../core"

// Slip (W53.7, docs/ux/styles.md §9 washi): a tooltip — and a toast, which the shell draws as the look's tooltip — as a
// slip of washi (短冊 tanzaku, 付箋): the paper a shade lighter than the sheet under it, a sumi hairline round it with the
// corners barely softened (2 px, as torn-and-trimmed paper), and a thin beni rule down its start edge, the slip's one
// colour. No tail, no shadow (paper lies flat; the card under it keeps its own elevation). Roles only (rule 4); static.
TooltipBase {
    id: tt
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property string fill: Theme.decor("tooltip.fill", "")
    readonly property int r: Math.max(0, Theme.decor("tooltip.radius", 2))
    Rectangle {
        anchors.fill: parent
        radius: tt.r
        color: tt.fill !== "" ? tt.fill : Theme.color("color.surface_container_lowest", "#fbf8f1")
        border.width: tt.hair
        border.color: Qt.alpha(Theme.fg, 0.55)
    }
    Rectangle {
        x: 4
        anchors { top: parent.top; bottom: parent.bottom; topMargin: 5; bottomMargin: 5 }
        width: Math.max(2, 2 * tt.hair)
        color: Theme.accent
        opacity: 0.85
    }
}
