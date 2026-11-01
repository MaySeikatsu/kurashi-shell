import QtQuick
import "../../../core"

// Glass (W53.2): a glass band — Windows 7's superbar (docs/ux/styles.md §3, measured from Microsoft's own Windows 7 UX
// guide capture learn.microsoft.com/…/uxguide/images/winenv-taskbar-image1.png, the bar at y 395–434): on the edge facing
// the screen's middle one dark px and one light px, then translucent glass — `[decor] bar.fill`'s role over a smoky
// shade, the blurred desktop showing through (the bar's own blur: the look's material) — with a soft gloss over the half
// toward that edge (`bar.gloss`). Under reduce transparency the look's material is opaque and so is this. Every colour
// from roles (rule 4); static.
BarBase {
    id: gl
    readonly property var fills: Theme.decor("bar.fill", [])
    readonly property color c: fills.length > 0 ? fills[0] : Theme.accent
    readonly property string edgeRole: Theme.decor("bar.edge", "")
    readonly property color lit: edgeRole !== "" ? edgeRole : Qt.rgba(1, 1, 1, 1)
    readonly property real g: Theme.decor("bar.gloss", 0.5)
    // The glass's own opacity: the theme's surface alpha (reduce transparency makes it 1).
    readonly property real a: Theme.tok("color.surface_alpha", 0.82)
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    readonly property bool flip: inner === "bottom" || inner === "right"

    // The smoke and the tint.
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.04, 0.07, 0.11, 0.42 * gl.a) }
    Rectangle { anchors.fill: parent; color: Qt.alpha(gl.c, 0.38 * gl.a) }
    // The gloss: the half toward the screen's middle, brightest at its edge, a sharp fall at the middle.
    Rectangle {
        x: gl.vertical ? (gl.flip ? gl.width / 2 : 0) : 0
        y: gl.vertical ? 0 : (gl.flip ? gl.height / 2 : 0)
        width: gl.vertical ? gl.width / 2 : gl.width
        height: gl.vertical ? gl.height : gl.height / 2
        gradient: Gradient {
            orientation: gl.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: gl.flip ? 1 : 0; color: Qt.rgba(1, 1, 1, 0.20 * gl.g) }
            GradientStop { position: gl.flip ? 0 : 1; color: Qt.rgba(1, 1, 1, 0.07 * gl.g) }
        }
    }
    // The two lines on the inner edge: dark, then light.
    Rectangle {
        color: Qt.rgba(0, 0, 0, 0.55)
        x: gl.inner === "right" ? gl.width - gl.hair : 0
        y: gl.inner === "bottom" ? gl.height - gl.hair : 0
        width: gl.vertical ? gl.hair : gl.width
        height: gl.vertical ? gl.height : gl.hair
    }
    Rectangle {
        color: Qt.alpha(gl.lit, 0.45)
        x: gl.inner === "right" ? gl.width - 2 * gl.hair : gl.inner === "left" ? gl.hair : 0
        y: gl.inner === "bottom" ? gl.height - 2 * gl.hair : gl.inner === "top" ? gl.hair : 0
        width: gl.vertical ? gl.hair : gl.width
        height: gl.vertical ? gl.height : gl.hair
    }
}
