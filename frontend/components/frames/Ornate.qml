import QtQuick
import "../../core"

// Dark Souls (decor souls; shellseikatsu `Widgets/ThemeDecor/OrnateFrame.qml`, `Panels/Lockscreen/LockStyleSouls.qml`).
// Cards: leather grain (sparse scratches and pores, one paint), a thin antique-gold hairline inset with nested corner
// brackets and a diamond at each corner. Small blocks: two small brackets, top-left and bottom-right. Ground: black
// leather with a bonfire glow low on the screen, ember motes (still: the original's drift forever), and a gold
// hairline frame with the corner flourishes round the screen. Gold = accent, ember = tertiary, bone = text.
FrameBase {
    id: f
    readonly property color gold: Theme.accent
    readonly property real inset: f.ground ? 28 : 5

    function hash(x) { var s = Math.sin(x * 12.9898) * 43758.5453; return s - Math.floor(s) }

    Canvas {
        visible: !f.small
        anchors.fill: parent
        opacity: f.ground ? 0.12 : 0.1
        property color bone: Theme.fg
        onBoneChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            g.fillStyle = "#000000"
            var n = Math.floor(width * height / 700)
            for (var i = 0; i < n; i++)
                g.fillRect(f.hash(i * 3.1) * width, f.hash(i * 7.7) * height, 1 + f.hash(i * 5.3), 1)
            g.strokeStyle = bone
            g.lineWidth = 0.6
            var m = f.ground ? 40 : 10
            for (var j = 0; j < m; j++) {
                var x = f.hash(j * 13.7) * width, y = f.hash(j * 17.3) * height, len = 12 + f.hash(j * 19.9) * 40
                g.beginPath()
                g.moveTo(x, y)
                g.lineTo(x + len, y + len * 0.25)
                g.stroke()
            }
        }
    }

    // Corner flourish: an outer L-bracket, an inner tick and a diamond; mirrored per corner.
    component Flourish: Item {
        id: fl
        property int corner: 0          // 0 TL, 1 TR, 2 BL, 3 BR
        property real k: 1
        width: 26 * k; height: 26 * k
        transform: Scale {
            xScale: (fl.corner === 1 || fl.corner === 3) ? -1 : 1
            yScale: (fl.corner === 2 || fl.corner === 3) ? -1 : 1
            origin.x: fl.width / 2; origin.y: fl.height / 2
        }
        Rectangle { width: 18 * fl.k; height: 2; color: f.gold; opacity: 0.9 }
        Rectangle { width: 2; height: 18 * fl.k; color: f.gold; opacity: 0.9 }
        Rectangle { x: 4 * fl.k; y: 4 * fl.k; width: 10 * fl.k; height: 1; color: f.gold; opacity: 0.6 }
        Rectangle { x: 4 * fl.k; y: 4 * fl.k; width: 1; height: 10 * fl.k; color: f.gold; opacity: 0.6 }
        Rectangle { x: 7 * fl.k; y: 7 * fl.k; width: 5 * fl.k; height: width; rotation: 45; color: f.gold; opacity: 0.85 }
    }
    // A small bracket for keys and bar groups.
    component Tick: Item {
        id: tk
        property int corner: 0
        width: 7; height: 7
        transform: Scale {
            xScale: tk.corner === 3 ? -1 : 1
            yScale: tk.corner === 3 ? -1 : 1
            origin.x: 3.5; origin.y: 3.5
        }
        Rectangle { width: 7; height: 1; color: f.gold; opacity: 0.8 }
        Rectangle { width: 1; height: 7; color: f.gold; opacity: 0.8 }
    }

    Item {
        visible: !f.small
        anchors.fill: parent
        readonly property real k: f.ground ? 2 : 1
        Rectangle {
            anchors { fill: parent; margins: f.inset }
            radius: Math.max(0, f.radius - f.inset)
            color: "transparent"
            border.width: 1
            border.color: f.gold
            opacity: 0.55
        }
        Flourish { corner: 0; k: parent.k; x: f.inset - 2; y: f.inset - 2 }
        Flourish { corner: 1; k: parent.k; x: f.width - width - f.inset + 2; y: f.inset - 2 }
        Flourish { corner: 2; k: parent.k; x: f.inset - 2; y: f.height - height - f.inset + 2 }
        Flourish { corner: 3; k: parent.k; x: f.width - width - f.inset + 2; y: f.height - height - f.inset + 2 }
    }
    Tick { visible: f.small && f.height >= 24; corner: 0; x: 3 + f.cornerInset; y: 3 }
    Tick { visible: f.small && f.height >= 24; corner: 3; x: f.width - 10 - f.cornerInset; y: f.height - 10 }

    // ---- ground: leather, the bonfire glow, embers ----
    Item {
        visible: f.ground
        anchors.fill: parent
        z: -1
        clip: true
        Rectangle { anchors.fill: parent; color: Qt.darker(Theme.surface, 1.5) }
        Glow {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: -height * 0.5 }
            width: parent.width * 0.9
            height: parent.height * 0.75
            color: Theme.tertiary
            alpha: 0.35
            mid: 0.35
        }
        Repeater {
            model: f.ground ? 9 : 0
            Rectangle {
                required property int index
                readonly property real seed: (index * 61.8) % 100 / 100
                width: 2 + seed * 3; height: width
                radius: width / 2
                color: index % 3 === 0 ? f.gold : Theme.tertiary
                opacity: 0.3 + seed * 0.5
                x: f.width * (0.3 + ((index * 0.067 + seed * 0.1) % 0.4))
                y: f.height * (0.62 + ((index * 0.13 + seed * 0.2) % 0.3))
            }
        }
    }
}
