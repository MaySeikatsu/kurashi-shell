import QtQuick
import "../../../core"

// Window (W53.5, docs/ux/styles.md §7): a tooltip as a small 16-bit RPG window — a dark outline one grid pixel wide, a
// white border one grid pixel wide, the corner stepped (no antialiasing), the fill the window's middle blue
// (`[decor] tooltip.fill`). Roles only (rule 4); static.
TooltipBase {
    id: tt
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    readonly property string fill: Theme.decor("tooltip.fill", "")
    readonly property int r: Math.max(0, Theme.decor("tooltip.radius", -1))
    Rectangle {
        anchors.fill: parent
        radius: tt.r
        antialiasing: false
        color: tt.fill !== "" ? tt.fill : Theme.color("color.surface_container", "#102070")
        border.width: tt.g
        border.color: Theme.color("color.line", "#000000")
    }
    Rectangle {
        anchors { fill: parent; margins: tt.g }
        radius: Math.max(0, tt.r - tt.g)
        antialiasing: false
        color: "transparent"
        border.width: tt.g
        border.color: Theme.color("color.ring", "#f8f8f8")
    }
}
