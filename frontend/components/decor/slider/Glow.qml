import QtQuick
import "../../../core"

// Glow (W53.5, docs/ux/styles.md §8): a PS2 dashboard slider — a silver hairline, the value's part a line of tower blue
// with a soft rise of light over it, and the knob a small bright point ringed in blue. High contrast (no glow): the lines
// solid. Roles only (rule 4); static.
SliderBase {
    id: sl
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property real v: Math.max(0, Math.min(1, value))
    readonly property int knob: 12
    readonly property real span: (vertical ? height : width) - knob
    Item {
        x: sl.vertical ? Math.round(sl.width / 2) : sl.knob / 2
        y: sl.vertical ? sl.knob / 2 : Math.round(sl.height / 2)
        width: sl.vertical ? sl.hair : sl.span
        height: sl.vertical ? sl.span : sl.hair
        Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.fg, Theme.glow > 0 ? 0.3 : 1) }
        Rectangle {
            width: sl.vertical ? 2 * sl.hair : parent.width * sl.v
            height: sl.vertical ? parent.height * sl.v : 2 * sl.hair
            y: sl.vertical ? parent.height - height : -sl.hair
            x: sl.vertical ? -sl.hair : 0
            color: Theme.accent
        }
        Rectangle {
            visible: Theme.glow > 0 && !sl.vertical
            width: parent.width * sl.v
            height: 8
            y: -height
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.alpha(Theme.glowColor, 0.3) }
            }
        }
    }
    Rectangle {
        width: sl.knob; height: sl.knob; radius: sl.knob / 2
        x: sl.vertical ? Math.round((sl.width - sl.knob) / 2) : Math.round(sl.span * sl.v)
        y: sl.vertical ? Math.round(sl.span * (1 - sl.v)) : Math.round((sl.height - sl.knob) / 2)
        color: Theme.fg
        border.width: 2
        border.color: Qt.alpha(Theme.accent, sl.pressed ? 1 : 0.8)
    }
}
