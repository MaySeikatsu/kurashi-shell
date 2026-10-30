import QtQuick
import "../../core"

// Windows XP "Luna" (decor luna; shellseikatsu `Widgets/SurfaceFrame.qml`, `Panels/Lockscreen/LockStyleXp.qml`).
// Cards: the blue window frame — an accent band round the edge, thicker and glossy along the top as the title bar's
// trace. Small blocks: the glossy XP button (a white sheen over the top half, a darker foot). Ground: the Welcome
// screen — a Luna-blue field between darker header and footer bands with the orange divider (tertiary).
FrameBase {
    id: f
    readonly property color band: Theme.accent
    readonly property real r: Math.max(0, f.radius)

    // ---- card: window band ----
    // W53.2: XP's 3 px window frame (measured on guidebookgallery.org's winxppro desktop, x 124–126 and 532–534: lit lines
    // on the left and top, darker ones on the right and bottom) in the caption's role (`[decor] border.color`), and,
    // for a card without a caption, the band's glossy trace along the top.
    readonly property string borderRole: Theme.decor("border.color", "")
    readonly property color frameC: borderRole !== "" ? borderRole : f.band
    readonly property int frameW: Math.max(1, Theme.decor("border.width", 3))
    Repeater {
        model: f.card ? f.frameW : 0
        Rectangle {
            required property int index
            anchors { fill: parent; margins: index }
            radius: Math.max(0, f.r - index)
            color: "transparent"
            border.width: 1
            border.color: index === 0 ? Qt.darker(f.frameC, 1.12) : index === 1 ? Qt.lighter(f.frameC, 1.12) : Qt.darker(f.frameC, 1.05)
        }
    }
    // The darker right and bottom lines (XP lit its frames from the top left).
    Rectangle {
        visible: f.card
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; topMargin: f.r; bottomMargin: f.r }
        width: Math.min(2, f.frameW)
        color: Qt.darker(f.frameC, 1.9)
        opacity: 0.85
    }
    Rectangle {
        visible: f.card
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: f.r; rightMargin: f.r }
        height: Math.min(2, f.frameW)
        color: Qt.darker(f.frameC, 1.9)
        opacity: 0.85
    }
    Rectangle {
        visible: f.card
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 7
        topLeftRadius: f.r
        topRightRadius: f.r
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(f.frameC, 1.45) }
            GradientStop { position: 0.45; color: f.frameC }
            GradientStop { position: 1.0; color: Qt.darker(f.frameC, 1.15) }
        }
    }

    // ---- small: glossy button ----
    Rectangle {
        visible: f.small
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1 }
        height: parent.height * 0.48
        topLeftRadius: Math.max(0, f.r - 1)
        topRightRadius: Math.max(0, f.r - 1)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, f.pressed ? 0.1 : 0.55) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
    Rectangle {
        visible: f.small
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                  leftMargin: f.r * 0.6 + 1; rightMargin: f.r * 0.6 + 1; bottomMargin: 1 }
        height: 1
        color: Qt.darker(Theme.containerHigh, 1.25)
    }

    // ---- ground: Welcome ----
    Item {
        visible: f.ground
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.lighter(f.band, 1.35) }
                GradientStop { position: 0.5; color: Qt.lighter(f.band, 1.5) }
                GradientStop { position: 1.0; color: Qt.lighter(f.band, 1.2) }
            }
        }
        Glow {
            anchors.centerIn: parent
            width: parent.width * 0.9
            height: parent.height * 0.6
            color: "#ffffff"
            alpha: 0.18
        }
        Rectangle {
            id: top
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: parent.height * 0.12
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.darker(f.band, 1.9) }
                GradientStop { position: 0.85; color: Qt.darker(f.band, 1.3) }
                GradientStop { position: 1.0; color: f.band }
            }
        }
        Rectangle {
            anchors { top: top.bottom; left: parent.left; right: parent.right }
            height: 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.7) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            id: foot
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: parent.height * 0.12
            gradient: Gradient {
                GradientStop { position: 0.0; color: f.band }
                GradientStop { position: 0.15; color: Qt.darker(f.band, 1.3) }
                GradientStop { position: 1.0; color: Qt.darker(f.band, 1.9) }
            }
        }
        Rectangle {
            anchors { bottom: foot.top; left: parent.left; right: parent.right }
            height: 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.lighter(Theme.tertiary, 1.5) }
                GradientStop { position: 0.6; color: Qt.lighter(Theme.tertiary, 1.25) }
                GradientStop { position: 1.0; color: Theme.tertiary }
            }
        }
    }
}
