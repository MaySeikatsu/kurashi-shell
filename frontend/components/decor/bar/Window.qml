import QtQuick
import "../../../core"

// Window (W53.5, docs/ux/styles.md §7): the bar as a 16-bit RPG HUD strip — one window along the edge, the party-status
// box of a battle screen (Final Fantasy VI's bottom window spans the screen): the look's banded fill across the bar's
// thickness (`[decor] fill.bands` / `fill.band_h`, top to bottom on a horizontal bar, left to right on a side one) inside
// the snes frame's rings — a dark outline, then white, light grey and dark grey, one grid pixel each — corners stepped (no
// antialiasing). One solid fill in high contrast (no bands: the white ring on black). Roles only (rule 4); static.
BarBase {
    id: w
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    readonly property real t: vertical ? width : height
    readonly property int n: Theme.bandCount(t - 8 * g, g)
    readonly property int r: Theme.rLg
    readonly property var rings: [Theme.color("color.line", "#000000"), Theme.color("color.ring", "#f8f8f8"),
        Theme.color("color.outline", "#b8b8b8"), Theme.color("color.outline_variant", "#606868")]

    Item {
        anchors { fill: parent; margins: 4 * w.g }
        Rectangle {
            visible: w.n < 2
            anchors.fill: parent
            antialiasing: false
            color: Theme.color("color.surface_container", "#181868")
        }
        Repeater {
            model: w.n > 1 ? w.n : 0
            Rectangle {
                required property int index
                readonly property real a: Math.round(index * (w.t - 8 * w.g) / w.n)
                readonly property real b: Math.round((index + 1) * (w.t - 8 * w.g) / w.n)
                x: w.vertical ? a : 0
                y: w.vertical ? 0 : a
                width: w.vertical ? b - a : parent.width
                height: w.vertical ? parent.height : b - a
                antialiasing: false
                color: Qt.tint(Theme.bandTop, Qt.alpha(Theme.bandBottom, index / (w.n - 1)))
            }
        }
    }
    Repeater {
        model: w.rings
        Rectangle {
            required property int index
            required property color modelData
            anchors { fill: parent; margins: index * w.g }
            radius: Math.max(0, w.r - index * w.g)
            antialiasing: false
            color: "transparent"
            border.width: w.g
            border.color: modelData
        }
    }
}
