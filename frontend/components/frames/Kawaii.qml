import QtQuick
import "../../core"

// Kawaii / Needy Streamer Overload (decor kawaii; shellseikatsu `Widgets/ThemeDecor/KawaiiFrame.qml`,
// `Panels/Lockscreen/LockStyleKawaii.qml`). Cards: the NSO window — a lavender title band with three tiny window
// buttons, a pastel checker strip, a pink double border, pixel hearts and sparkles. Small blocks that are wide (bar
// groups, pills): a checker strip along the bottom. Ground: a pastel checkered desktop with scattered pixel hearts.
// Pink = accent, lavender = secondary, the bubble = tertiary, paper = ring, ink = text.
FrameBase {
    id: f
    readonly property color pink: Theme.accent
    readonly property color lavender: Qt.lighter(Theme.secondary, 1.35)
    readonly property color bubble: Qt.lighter(Theme.tertiary, 1.6)
    readonly property color paper: Theme.ring
    readonly property color ink: Theme.fg

    // A heart = two head squares + a 5-wide row + a 3-wide body + a 1-wide tip (5×4 hard pixels, scaled).
    component PixelHeart: Item {
        id: ph
        property real px: 2.4
        property color tone: f.pink
        width: px * 5; height: px * 4
        Rectangle { x: 0; y: 0; width: ph.px * 2; height: ph.px; color: ph.tone }
        Rectangle { x: ph.px * 3; y: 0; width: ph.px * 2; height: ph.px; color: ph.tone }
        Rectangle { x: 0; y: ph.px; width: ph.px * 5; height: ph.px; color: ph.tone }
        Rectangle { x: ph.px; y: ph.px * 2; width: ph.px * 3; height: ph.px; color: ph.tone }
        Rectangle { x: ph.px * 2; y: ph.px * 3; width: ph.px; height: ph.px; color: ph.tone }
    }
    component Sparkle: Item {
        id: sp
        property real px: 2
        property color tone: f.bubble
        width: px * 3; height: px * 3
        Rectangle { x: sp.px; y: 0; width: sp.px; height: sp.px * 3; color: sp.tone }
        Rectangle { x: 0; y: sp.px; width: sp.px * 3; height: sp.px; color: sp.tone }
    }
    component Checker: Row {
        id: ck
        property real cell: 6
        property real h: 3
        property real w: 100
        clip: true
        width: w
        Repeater {
            model: Math.ceil(ck.w / ck.cell)
            Rectangle {
                required property int index
                width: ck.cell; height: ck.h
                color: index % 2 === 0 ? f.lavender : f.paper
            }
        }
    }

    // ---- card: pink double border, title band with window buttons, checker strip, hearts ----
    Item {
        visible: f.card
        anchors.fill: parent
        Rectangle {
            anchors { fill: parent; margins: 3 }
            radius: Math.max(0, f.radius - 3)
            color: "transparent"
            border.width: 2
            border.color: f.pink
            opacity: 0.55
        }
        Rectangle {
            anchors { fill: parent; margins: 6 }
            radius: Math.max(0, f.radius - 6)
            color: "transparent"
            border.width: 1
            border.color: f.lavender
        }
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 6 }
            height: 8
            topLeftRadius: Math.max(0, f.radius - 6)
            topRightRadius: Math.max(0, f.radius - 6)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: f.lavender }
                GradientStop { position: 1.0; color: Qt.lighter(f.lavender, 1.12) }
            }
            Row {
                anchors { right: parent.right; rightMargin: Math.max(5, f.radius * 0.5); verticalCenter: parent.verticalCenter }
                spacing: 3
                Repeater {
                    model: 3
                    Rectangle { width: 6; height: 6; radius: 1.5; color: f.paper; border.width: 1; border.color: f.ink; opacity: 0.85 }
                }
            }
        }
        Checker {
            x: 6 + f.cornerInset * 0.3
            y: 14
            w: f.width - 2 * x
            opacity: 0.5
        }
        PixelHeart { visible: f.width > 180; x: 14 + f.cornerInset; y: f.height - 18; px: 2; opacity: 0.7 }
        PixelHeart { visible: f.width > 180; x: f.width - 26 - f.cornerInset; y: f.height - 20; px: 1.6; tone: f.lavender }
        Sparkle { x: f.width * 0.34; y: f.height - 14; opacity: 0.7 }
        Sparkle { x: f.width * 0.72; y: 22; px: 1.6; tone: f.pink; opacity: 0.45 }
    }

    // ---- small and wide: a checker strip along the bottom ----
    Checker {
        visible: f.small && f.width >= f.height * 2.5
        x: f.cornerInset + 6
        y: f.height - 4
        w: f.width - 2 * x
        cell: 5
        h: 2
        opacity: 0.6
    }

    // ---- ground: pastel checkered desktop, scattered hearts ----
    Canvas {
        visible: f.ground
        anchors.fill: parent
        property color a: Theme.surface
        property color b: Theme.containerHigh
        onAChanged: requestPaint()
        onBChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var g = getContext("2d")
            g.reset()
            g.fillStyle = String(a)
            g.fillRect(0, 0, width, height)
            g.fillStyle = String(b)
            var s = 32
            for (var y = 0; y < height; y += s)
                for (var x = ((y / s) % 2) * s; x < width; x += 2 * s)
                    g.fillRect(x, y, s, s)
        }
    }
    Repeater {
        model: f.ground ? 14 : 0
        PixelHeart {
            required property int index
            readonly property real seed: (index * 61.8) % 100 / 100
            x: f.width * ((index * 0.137 + seed * 0.21) % 1)
            y: f.height * ((index * 0.291 + seed * 0.37) % 1)
            px: 3 + seed * 3
            tone: index % 3 === 0 ? f.lavender : (index % 3 === 1 ? f.pink : f.bubble)
            opacity: 0.5
        }
    }
}
