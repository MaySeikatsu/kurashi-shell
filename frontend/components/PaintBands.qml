import QtQuick
import "../core"

// The ground of a painted surface larger than one stroke (I471b; the user's mock-up of a desktop widget: a clock on one
// broad stroke, a calendar on three): bands of a brush, one under another, each starting and stopping at its own place
// and lapping over the next, so the surface is covered as a brush would cover it. A surface no taller than a stroke is
// one stroke. Fill the surface with it; it draws past the surface's sides. Static.
Item {
    id: pb
    property color color: Qt.alpha(Theme.accent, 0.5)
    // A column or a strip brushed freely (the sidebar, the dock): the bands lean and wander more.
    property bool wild: false
    property real blend: Theme.paintBlend
    // How many bands: from the height, but only once it has stood still for a moment: a surface that is opening or
    // morphing keeps its bands (they stretch with it) instead of gaining and losing strokes on the way.
    property int n: Math.max(1, Math.round(height / 74))
    onHeightChanged: settle.restart()
    Timer { id: settle; interval: 140; onTriggered: { var k = Math.max(1, Math.round(pb.height / 74)); if (k !== pb.n) pb.n = k } }
    Component.onCompleted: n = Math.max(1, Math.round(height / 74))
    // (the bands' own chances: drawn once, not from the size)
    readonly property real salt: Math.random() * 1000
    readonly property real step: height / n
    function rnd(i: int, k: int): real {
        var v = Math.sin((i + 1) * 127.1 + k * 311.7 + pb.salt) * 43758.5453
        return v - Math.floor(v)
    }
    // The strokes; and, while the shell wears a material (`theme.texture`), that material's relief on them and only on
    // them: the strokes drawn once into a texture (redrawn when they change, never per frame) clip a Relief laid over
    // the surface and the room the strokes overshoot into. Without a material a stroke carries its own bristle lines.
    readonly property real reach: 64
    Item {
        id: strokes
        anchors.fill: parent
        Repeater {
            model: pb.n
            PaintStroke {
                required property int index
                // Each band is its own stroke of the hand: it laps the next by a third or more, is set in or out at its two
                // ends by up to a seventh of the width, sits a little high or low and leans a degree or two.
                readonly property real lap: pb.n > 1 ? pb.step * (0.3 + 0.3 * pb.rnd(index, 4)) : 0
                readonly property real inL: (pb.rnd(index, 1) - 0.4) * Math.min(44, pb.width * 0.14) * (pb.wild ? 1.5 : 1)
                readonly property real inR: (pb.rnd(index, 2) - 0.4) * Math.min(52, pb.width * 0.16) * (pb.wild ? 1.5 : 1)
                x: inL
                y: index * pb.step - lap / 2 + (pb.rnd(index, 5) - 0.5) * Math.min(8, pb.step * 0.12)
                width: pb.width - inL - inR
                height: pb.step + lap
                // (each stroke has its own direction: up to about six degrees either way, ten on a column brushed freely; less on
                // a long one, whose ends would otherwise leave the surface; a single stroke under a control leans a little)
                rotation: (pb.rnd(index, 6) - 0.5) * 2 * Math.min(pb.wild ? 10 : (pb.n > 1 ? 6 : 2.5),
                    Math.atan(Math.max(8, pb.step * (pb.n > 1 ? 0.55 : 0.2)) / Math.max(40, pb.width / 2)) * 180 / Math.PI)
                seedShift: index * 11 + 3
                color: pb.color
                blend: pb.blend
            }
        }
    }
    readonly property bool lit: Theme.texShell && !Theme.texText
    Loader {
        active: pb.lit
        x: -pb.reach
        y: -pb.reach
        width: pb.width + 2 * pb.reach
        height: pb.height + 2 * pb.reach
        sourceComponent: Item {
            ShaderEffectSource {
                id: cut
                anchors.fill: parent
                visible: false
                sourceItem: strokes
                sourceRect: Qt.rect(-pb.reach, -pb.reach, pb.width + 2 * pb.reach, pb.height + 2 * pb.reach)
                live: false
                Connections {
                    target: pb
                    function onWidthChanged() { Qt.callLater(cut.scheduleUpdate) }
                    function onHeightChanged() { Qt.callLater(cut.scheduleUpdate) }
                    function onNChanged() { Qt.callLater(cut.scheduleUpdate) }
                    function onColorChanged() { Qt.callLater(cut.scheduleUpdate) }
                }
                Component.onCompleted: Qt.callLater(cut.scheduleUpdate)
            }
            Relief { anchors.fill: parent; mask: cut }
        }
    }
}
