import QtQuick
import "../../core"

// PaneMark (W53.2): an original start mark in the spirit of the glossy era — four soft panes in a slanted 2 × 2 window,
// each lit from its top left, never a vendor's logo (docs/ux/styles.md "Original marks"): straight panes, no wave, no
// flag. The panes take palette roles (`error`, `secondary`, `accent`, `tertiary`, each lifted toward white by `lift`),
// so a pinned palette still fits (rule 4). `glow` adds a soft light round it (7's orb). Static.
Item {
    id: pm
    property real size: 20
    property real lift: 0.25
    property real glow: 0
    property real slant: 0.12
    width: size
    height: size
    readonly property real gap: Math.max(1, Math.round(size * 0.07))
    readonly property real cell: (size - gap) / 2
    function tone(c) { return Qt.tint(c, Qt.rgba(1, 1, 1, pm.lift)) }
    readonly property var inks: [tone(Theme.error), tone(Qt.lighter(Theme.secondary, 1.35)), tone(Qt.lighter(Theme.accent, 1.3)),
        tone(Theme.tertiary)]

    Rectangle {
        visible: pm.glow > 0
        anchors.centerIn: parent
        width: pm.size * 1.5; height: pm.size * 1.5
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.35 * pm.glow) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
    Item {
        anchors.fill: parent
        // The window leans forward a little: a shear, not a wave.
        transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -pm.slant, 0, pm.slant * pm.size / 2, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
        Repeater {
            model: 4
            Item {
                required property int index
                x: (index % 2) * (pm.cell + pm.gap)
                y: Math.floor(index / 2) * (pm.cell + pm.gap)
                width: pm.cell
                height: pm.cell
                Rectangle {
                    anchors.fill: parent
                    radius: Math.max(1, pm.cell * 0.2)
                    color: pm.inks[parent.index]
                    border.width: pm.size >= 18 ? 1 : 0
                    border.color: Qt.darker(pm.inks[parent.index], 1.45)
                }
                Rectangle {
                    x: 1; y: 1
                    width: parent.width - 2; height: parent.height * 0.5
                    radius: Math.max(1, pm.cell * 0.18)
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.55) }
                        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.05) }
                    }
                }
            }
        }
    }
}
