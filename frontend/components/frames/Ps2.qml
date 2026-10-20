import QtQuick
import "../../core"

// PS2 dashboard (decor ps2; shellseikatsu `Widgets/ThemeDecor/Ps2Frame.qml`, `Panels/Lockscreen/LockStylePs2.qml`).
// Cards: faint light towers rising from the bottom (one Canvas paint), a few sparkle motes and a blue glow line along
// the bottom edge. Small blocks: the glow line. Ground: the void with a deep blue floor glow and taller towers that
// rise once when the surface appears (only while `animate`). The original's motes drift forever; here they stand
// still (Ma: an idle shell renders no frames). Tower blue = accent, deep blue = tertiary.
FrameBase {
    id: f
    readonly property color blue: Theme.accent
    readonly property color deep: Theme.tertiary

    function hash(x) { var s = Math.sin(x * 12.9898) * 43758.5453; return s - Math.floor(s) }

    Canvas {
        visible: f.card
        anchors.fill: parent
        opacity: 0.22
        property color c: f.blue
        onCChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            var n = 5 + Math.floor(f.hash(width) * 3)
            for (var i = 0; i < n; i++) {
                var w = 6 + f.hash(i * 5.3) * 10
                var x = f.hash(i * 3.1) * (width - w)
                var h = height * (0.25 + f.hash(i * 7.7) * 0.5)
                var gr = g.createLinearGradient(0, height - h, 0, height)
                gr.addColorStop(0, Qt.alpha(Qt.lighter(c, 1.3), 0.55))
                gr.addColorStop(0.15, Qt.alpha(c, 0.3))
                gr.addColorStop(1, Qt.alpha(c, 0.03))
                g.fillStyle = gr
                g.fillRect(x, height - h, w, h)
                g.fillStyle = Qt.alpha(Qt.lighter(c, 1.4), 0.7)
                g.fillRect(x, height - h, w, 1.5)
            }
        }
    }
    Repeater {
        model: f.card ? 5 : (f.ground ? 14 : 0)
        Rectangle {
            required property int index
            readonly property real seed: (index * 61.8) % 100 / 100
            width: (f.ground ? 2.5 : 1.5) + seed * 2
            height: width
            radius: width / 2
            color: index % 2 === 0 ? f.blue : Theme.fg
            opacity: 0.35 + 0.4 * seed
            x: f.width * (0.08 + ((index * 0.19 + seed * 0.15) % 0.84))
            y: f.height * (0.12 + ((index * 0.37 + seed * 0.3) % 0.7))
        }
    }
    Rectangle {
        visible: !f.ground
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                  bottomMargin: f.card ? 4 : 1
                  leftMargin: Math.max(f.card ? 6 : 2, f.radius * 0.5)
                  rightMargin: Math.max(f.card ? 6 : 2, f.radius * 0.5) }
        height: f.card ? 2 : 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: f.deep }
            GradientStop { position: 1.0; color: "transparent" }
        }
        opacity: f.card ? 0.8 : 0.9
    }

    // ---- ground ----
    Item {
        visible: f.ground
        anchors.fill: parent
        z: -1
        clip: true
        Rectangle { anchors.fill: parent; color: Qt.darker(Theme.surface, 1.6) }
        Glow {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: -height * 0.5 }
            width: parent.width * 1.3
            height: parent.height * 0.9
            color: f.deep
            alpha: 0.55
        }
        Repeater {
            model: f.ground ? 9 : 0
            Rectangle {
                id: tower
                required property int index
                readonly property real seed: (index * 61.8) % 100 / 100
                readonly property real targetH: f.height * (0.18 + seed * 0.4)
                x: f.width * (0.06 + index * 0.105 + seed * 0.02)
                anchors.bottom: parent.bottom
                width: f.width * (0.008 + seed * 0.014)
                height: f.animate ? 0 : targetH
                opacity: 0.5
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.lighter(f.blue, 1.4) }
                    GradientStop { position: 0.12; color: f.blue }
                    GradientStop { position: 1.0; color: Qt.alpha(f.deep, 0.1) }
                }
                Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 2
                            color: Qt.lighter(f.blue, 1.5); opacity: 0.9 }
                // One rise when the surface appears; it ends, then nothing runs (Ma).
                NumberAnimation on height {
                    running: f.animate
                    from: 0
                    to: tower.targetH
                    duration: 2400 + tower.seed * 2600
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
