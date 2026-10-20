import QtQuick
import "../../core"

// NieR: Automata / YoRHa (decor yorha; shellseikatsu `Widgets/ThemeDecor/YorhaFrame.qml`,
// `Panels/Lockscreen/LockStyleNier.qml`): faint scanlines, the signature double rule (thick + thin) along the top, a
// dither strip of fading squares under it and a hairline near the bottom. Small blocks keep the bottom hairline only.
// Ground: scanlines over the whole surface, the double rules and dither strips above and below the column. Ink is
// the text role, so the frame follows any palette.
FrameBase {
    id: f
    readonly property color ink: Theme.fg
    readonly property real insetX: (f.ground ? f.width * 0.1 : 10) + f.cornerInset

    Canvas {
        visible: !f.small
        anchors.fill: parent
        opacity: f.ground ? 0.12 : 0.05
        property color ink: f.ink
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            g.fillStyle = String(ink)
            for (var y = 2; y < height; y += 4)
                g.fillRect(0, y, width, 1)
        }
    }

    component Rules: Column {
        id: rules
        property real w: 100
        property int squares: 24
        property real sq: 4
        spacing: 2
        Rectangle { width: rules.w; height: 2; color: f.ink; opacity: 0.75 }
        Rectangle { width: rules.w; height: 1; color: f.ink; opacity: 0.4 }
        Item { width: 1; height: 1 }
        Row {
            visible: rules.w > 160
            spacing: 3
            Repeater {
                model: Math.max(0, Math.min(rules.squares, Math.floor(rules.w / 7)))
                Rectangle {
                    required property int index
                    width: rules.sq; height: width
                    color: f.ink
                    opacity: (index % 2 === 0 ? 0.4 : 0.18) * (1.0 - index / (rules.squares + 2))
                }
            }
        }
    }

    Rules {
        visible: f.card
        x: f.insetX
        y: 6
        w: f.width - 2 * f.insetX
    }
    Rectangle {
        visible: !f.ground
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                  bottomMargin: f.card ? 6 : 2; leftMargin: f.small ? f.cornerInset + 4 : f.insetX
                  rightMargin: f.small ? f.cornerInset + 4 : f.insetX }
        height: 1
        color: f.ink
        opacity: 0.35
    }

    // ---- ground ----
    Rules {
        visible: f.ground
        x: f.insetX
        y: f.height * 0.1
        w: f.width - 2 * f.insetX
        squares: 42
        sq: 5
    }
    Rules {
        visible: f.ground
        x: f.insetX
        y: f.height * 0.86
        w: f.width - 2 * f.insetX
        squares: 42
        sq: 5
    }
}
