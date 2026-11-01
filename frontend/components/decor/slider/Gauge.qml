import QtQuick
import "../../../core"

// Gauge (W53.5, docs/ux/styles.md §7): a slider as a 16-bit RPG gauge (an HP or ATB bar) on the pixel grid — a dark
// outline and a white border one grid pixel each round a dark well, the value filled in the accent in whole grid pixels,
// and the knob a small white block standing on the gauge. No antialiasing; roles only (rule 4); static.
SliderBase {
    id: gg
    readonly property int g: Math.max(1, Theme.grid(Screen.height) || 2)
    readonly property real v: Math.max(0, Math.min(1, value))
    readonly property int thick: 6 * g
    readonly property real len: vertical ? height : width
    readonly property real inner: Math.max(0, len - 6 * g)
    readonly property real filled: Math.round(inner * v / g) * g
    Item {
        x: gg.vertical ? Math.round((gg.width - gg.thick) / 2 / gg.g) * gg.g : 0
        y: gg.vertical ? 0 : Math.round((gg.height - gg.thick) / 2 / gg.g) * gg.g
        width: gg.vertical ? gg.thick : gg.width
        height: gg.vertical ? gg.height : gg.thick
        Rectangle { anchors.fill: parent; antialiasing: false; color: Theme.color("color.line", "#000000") }
        Rectangle {
            anchors { fill: parent; margins: gg.g }
            antialiasing: false
            color: Theme.color("color.surface_container_lowest", "#000820")
            border.width: gg.g
            border.color: Theme.color("color.ring", "#f8f8f8")
        }
        Rectangle {
            antialiasing: false
            x: gg.vertical ? 3 * gg.g : 3 * gg.g
            y: gg.vertical ? parent.height - 3 * gg.g - height : 3 * gg.g
            width: gg.vertical ? parent.width - 6 * gg.g : gg.filled
            height: gg.vertical ? gg.filled : parent.height - 6 * gg.g
            color: gg.pressed ? Qt.lighter(Theme.accent, 1.15) : Theme.accent
        }
    }
}
