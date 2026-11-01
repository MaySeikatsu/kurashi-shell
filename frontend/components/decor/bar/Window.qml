import QtQuick
import "../../../core"

// Window (W53.5, docs/ux/styles.md §7): the bar as a 16-bit RPG HUD strip — one window along the edge, the party-status
// box of a battle screen: the look's banded fill across the bar's thickness (`[decor] fill.bands`, `Theme.bandTop` on the
// side facing the screen's middle... drawn top to bottom on a horizontal bar, left to right on a side one), a dark outline
// one grid pixel wide and a white border two grid pixels wide, corners stepped (no antialiasing). Solid in high contrast
// (no bands: white border on black). Roles only (rule 4); static.
BarBase {
    id: w
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    readonly property int n: Math.max(1, Theme.fillBands)
    readonly property real t: vertical ? width : height
    readonly property int r: Theme.rLg

    Rectangle {
        anchors.fill: parent
        radius: w.r
        antialiasing: false
        color: Theme.color("color.line", "#000000")
    }
    // The bands, inside the border.
    Item {
        anchors { fill: parent; margins: 3 * w.g }
        Repeater {
            model: w.n
            Rectangle {
                required property int index
                readonly property real a: Math.round(index * (w.t - 6 * w.g) / w.n)
                readonly property real b: Math.round((index + 1) * (w.t - 6 * w.g) / w.n)
                x: w.vertical ? a : 0
                y: w.vertical ? 0 : a
                width: w.vertical ? b - a : parent.width
                height: w.vertical ? parent.height : b - a
                antialiasing: false
                color: Theme.fillBands > 1 ? Qt.tint(Theme.bandTop, Qt.alpha(Theme.bandBottom, index / (w.n - 1)))
                                           : Theme.color("color.surface_container", "#102070")
            }
        }
    }
    Rectangle {
        anchors { fill: parent; margins: w.g }
        radius: Math.max(0, w.r - w.g)
        antialiasing: false
        color: "transparent"
        border.width: 2 * w.g
        border.color: Theme.color("color.ring", "#f8f8f8")
    }
}
