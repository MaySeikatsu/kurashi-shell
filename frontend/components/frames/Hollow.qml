import QtQuick
import "../../core"

// Hollow Knight (decor hallownest; shellseikatsu `Widgets/ThemeDecor/HollowFrame.qml`,
// `Panels/Lockscreen/LockStyleHollow.qml`). Cards: the large symmetrical filigree — swooping quill curls flanking a
// bordered centre diamond — across the top, a smaller mirrored flourish at the bottom, and a few pale motes (still: the
// original's drift forever, an idle shell renders nothing). Small blocks: nothing (line chrome already draws the pale
// line work). Ground: Hallownest fog — a deep gradient, two fog banks — and the filigree large above and below the
// column. Pale = accent, fog = secondary.
FrameBase {
    id: f
    readonly property color pale: Theme.accent

    // One filigree: mirrored quills with end curls and echo arcs, and the centre diamond.
    component Filigree: Item {
        id: fg
        property bool flip: false
        property real line: 1.4
        Canvas {
            anchors.fill: parent
            property color c: f.pale
            onCChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            transform: Scale { yScale: fg.flip ? -1 : 1; origin.y: fg.height / 2 }
            onPaint: {
                var g = getContext("2d")
                g.reset()
                var cy = height * 0.55, half = width / 2, k = height / 22
                g.strokeStyle = c
                g.fillStyle = c
                g.lineWidth = fg.line
                for (var dir = -1; dir <= 1; dir += 2) {
                    g.globalAlpha = 0.85
                    g.beginPath()
                    g.moveTo(half + dir * 18 * k, cy)
                    g.bezierCurveTo(half + dir * half * 0.45, cy - 12 * k, half + dir * half * 0.75, cy - 2 * k,
                                    half + dir * half * 0.96, cy - 8 * k)
                    g.bezierCurveTo(half + dir * half * 1.0, cy - 10 * k, half + dir * half * 0.99, cy - 3 * k,
                                    half + dir * half * 0.93, cy - 4 * k)
                    g.stroke()
                    g.globalAlpha = 0.45
                    g.beginPath()
                    g.moveTo(half + dir * 20 * k, cy + 4 * k)
                    g.bezierCurveTo(half + dir * half * 0.4, cy + 9 * k, half + dir * half * 0.6, cy + 3 * k,
                                    half + dir * half * 0.72, cy + 5 * k)
                    g.stroke()
                    g.globalAlpha = 0.85
                    g.beginPath()
                    g.arc(half + dir * half * 0.93, cy - 4 * k, 1.6 * k, 0, 2 * Math.PI)
                    g.fill()
                }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: fg.height * 0.45; height: width
            rotation: 45
            color: "transparent"
            border.width: fg.line
            border.color: f.pale
        }
        Rectangle {
            anchors.centerIn: parent
            width: fg.height * 0.18; height: width
            rotation: 45
            color: f.pale
        }
    }

    Filigree {
        visible: f.card && f.width > 160
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 3 }
        width: Math.min(parent.width * 0.8, 380)
        height: 18
    }
    Filigree {
        visible: f.card && f.width > 160 && f.height > 120
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 3 }
        width: Math.min(parent.width * 0.5, 220)
        height: 12
        line: 1.1
        flip: true
        opacity: 0.7
    }
    Repeater {
        model: f.card ? 4 : (f.ground ? 12 : 0)
        Rectangle {
            required property int index
            readonly property real seed: (index * 61.8) % 100 / 100
            width: 2 + seed * 2.5; height: width
            radius: width / 2
            color: f.pale
            opacity: 0.18 + seed * 0.3
            x: f.width * (0.12 + ((index * 0.23 + seed * 0.1) % 0.76))
            y: f.height * (0.2 + ((index * 0.31 + seed * 0.2) % 0.65))
        }
    }

    // ---- ground ----
    Item {
        visible: f.ground
        anchors.fill: parent
        z: -1
        clip: true
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.containerHigh }
                GradientStop { position: 0.65; color: Theme.surface }
                GradientStop { position: 1.0; color: Qt.darker(Theme.surface, 1.4) }
            }
        }
        Glow { x: -parent.width * 0.15; y: parent.height * 0.5; width: parent.width; height: parent.height * 0.45
               color: Theme.secondary; alpha: 0.12 }
        Glow { x: parent.width * 0.35; y: parent.height * 0.65; width: parent.width * 0.8; height: parent.height * 0.4
               color: f.pale; alpha: 0.07 }
        Filigree {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.verticalCenter; bottomMargin: 200 }
            width: Math.min(parent.width * 0.6, 560)
            height: 34
            line: 1.8
        }
        Filigree {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.verticalCenter; topMargin: 190 }
            width: Math.min(parent.width * 0.4, 360)
            height: 24
            flip: true
            opacity: 0.7
        }
    }
}
