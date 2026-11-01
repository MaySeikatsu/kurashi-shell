import QtQuick
import "../../core"

// PS2 dashboard (decor ps2; shellseikatsu `Widgets/ThemeDecor/Ps2Frame.qml`, `Panels/Lockscreen/LockStylePs2.qml`).
// Cards: faint light towers rising from the bottom (one Canvas paint), a few sparkle motes and a blue glow line along
// the bottom edge. Small blocks: the glow line. Ground: the void with a deep blue floor glow and taller towers that
// rise once when the surface appears (only while `animate`). The original's motes drift forever; here they stand
// still (Ma: an idle shell renders no frames). Tower blue = tertiary lifted, deep blue = tertiary (W53.5: the accent is
// the selection's light blue).
FrameBase {
    id: f
    readonly property color blue: Qt.lighter(Theme.tertiary, 1.15)
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
    // W53.5 (lead review): the boot scene's towers are light, not columns. Each is painted once per size into its own
    // Canvas — a wide faint halo, a narrower body and a bright core, added together (`lighter`), the whole faded out toward
    // the top (no cut edge) and mirrored faintly under the floor line as a reflection — then revealed by a clip that rises
    // once when the surface appears (only while `animate`; at full height at once otherwise). Depth varies: the further a
    // tower (`d` → 1) the narrower, shorter and dimmer it is, and the deeper its blue; the far ones stand behind. A floor glow
    // lies along the line they stand on. Nothing repaints or runs after the rise (Ma).
    Item {
        id: groundItem
        visible: f.ground
        anchors.fill: parent
        z: -1
        clip: true
        readonly property real floorY: Math.round(height * 0.8)
        readonly property real reflH: height - floorY
        Rectangle { anchors.fill: parent; color: Qt.darker(Theme.surface, 1.6) }
        Glow {
            x: -parent.width * 0.15
            width: parent.width * 1.3
            height: parent.height * 0.5
            y: groundItem.floorY - height * 0.5
            color: f.deep
            alpha: 0.5
        }
        // A thin line of light where the towers meet the floor.
        Rectangle {
            x: parent.width * 0.04; width: parent.width * 0.92
            y: groundItem.floorY; height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.alpha(f.blue, 0.35) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Repeater {
            model: f.ground ? 11 : 0
            Item {
                id: tower
                required property int index
                readonly property real seed: (index * 61.8 + 13) % 100 / 100
                readonly property real seed2: (index * 37.3 + 71) % 100 / 100
                // Depth: the far ones (d → 1) are narrower, shorter, dimmer and drawn first (behind).
                readonly property real d: seed2
                z: 2 - d
                readonly property real coreW: f.width * (0.01 + seed * 0.016) * (1 - 0.45 * d)
                readonly property real fullH: groundItem.floorY * (0.32 + seed * 0.45) * (1 - 0.3 * d)
                readonly property real reach: coreW * 5
                property real shown: f.animate ? 0 : 1
                x: Math.round(f.width * (0.05 + index * 0.087 + (seed - 0.5) * 0.03) - reach / 2)
                width: Math.round(reach)
                // The clip: from the floor up `shown` of the height, and the reflection down in step.
                y: groundItem.floorY - fullH * shown
                height: (fullH + groundItem.reflH * 0.5) * shown
                clip: true
                NumberAnimation on shown {
                    running: f.animate
                    from: 0; to: 1
                    duration: 2400 + tower.seed * 2600
                    easing.type: Easing.OutCubic
                }
                Canvas {
                    id: light
                    width: tower.width
                    height: tower.fullH + groundItem.reflH * 0.5
                    // (its floor line stays on the floor while the clip opens)
                    y: -tower.fullH * (1 - tower.shown)
                    readonly property color c: Qt.tint(f.blue, Qt.alpha(f.deep, 0.5 * tower.d))
                    readonly property real a: 0.85 - 0.45 * tower.d
                    onCChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        var g = getContext("2d")
                        g.reset()
                        var W = width, H = tower.fullH, R = height - H
                        if (W <= 0 || H <= 0) return
                        var cx = W / 2, cw = tower.coreW
                        g.globalCompositeOperation = "lighter"
                        function band(half, alpha, col) {
                            var gr = g.createLinearGradient(cx - half, 0, cx + half, 0)
                            gr.addColorStop(0, Qt.alpha(col, 0))
                            gr.addColorStop(0.5, Qt.alpha(col, alpha))
                            gr.addColorStop(1, Qt.alpha(col, 0))
                            g.fillStyle = gr
                            g.fillRect(cx - half, 0, 2 * half, height)
                        }
                        band(W / 2, 0.16 * light.a, light.c)                       // the halo
                        band(cw * 1.5, 0.42 * light.a, light.c)                    // the body
                        band(cw * 0.4, 0.6 * light.a, Qt.lighter(light.c, 1.5))    // the core
                        // Fade: nothing at the top, full by 45 % down, a little brighter at the foot; the reflection
                        // under the floor starts at a third and is gone halfway down.
                        g.globalCompositeOperation = "destination-in"
                        var fade = g.createLinearGradient(0, 0, 0, height)
                        var fh = H / height
                        fade.addColorStop(0, "rgba(0,0,0,0)")
                        fade.addColorStop(fh * 0.45, "rgba(0,0,0,0.85)")
                        fade.addColorStop(fh * 0.999, "rgba(0,0,0,1)")
                        fade.addColorStop(Math.min(1, fh + 0.0005), "rgba(0,0,0,0.3)")
                        fade.addColorStop(1, "rgba(0,0,0,0)")
                        g.fillStyle = fade
                        g.fillRect(0, 0, W, height)
                    }
                }
            }
        }
    }
}
