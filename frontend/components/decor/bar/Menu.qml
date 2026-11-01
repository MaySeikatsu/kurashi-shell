import QtQuick
import "../../../core"
import ".."

// Menu (W53.4): a menu bar's ground — Mac OS X 10.2–10.4's and macOS 11–14's (docs/ux/styles.md §5, §6). `[decor]
// bar.fill` (one role solid, two a gradient from the screen's edge inward) at the material's alpha — opaque under a
// solid look (Aqua's white bar), translucent over the compositor's blur under a translucent one (macOS 11+); the look's
// ground pattern across it (Jaguar's pinstripes); `bar.gloss` lightens the half by the screen's edge; on the side facing
// the screen's middle a hairline in `bar.edge` ("" = none: macOS 11+ draws none) with a soft shade beyond it while it
// is opaque (10.x's menu bar cast one). Every colour from roles (rule 4); static.
BarBase {
    id: mb
    readonly property var fills: Theme.decor("bar.fill", [])
    readonly property color from: fills.length > 0 ? fills[0] : Theme.surface
    readonly property color to: fills.length > 1 ? fills[1] : from
    readonly property string edgeRole: Theme.decor("bar.edge", "")
    readonly property real g: Theme.decor("bar.gloss", 0)
    readonly property real a: Theme.tok("color.surface_alpha", 1)
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    // Toward the screen's middle (the gradient's end, the line's side).
    readonly property bool flip: inner === "top" || inner === "left"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: mb.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: mb.flip ? 1 : 0; color: Qt.alpha(Qt.tint(mb.from, Qt.rgba(1, 1, 1, 0.5 * mb.g)), mb.a) }
            GradientStop { position: 0.5; color: Qt.alpha(Qt.tint(mb.from, Qt.rgba(1, 1, 1, 0.2 * mb.g)), mb.a) }
            GradientStop { position: mb.flip ? 0 : 1; color: Qt.alpha(mb.to, mb.a) }
        }
    }
    Pattern { anchors.fill: parent }
    // The line on the inner edge, then (opaque only) a 3 px shade beyond it.
    Rectangle {
        visible: mb.edgeRole !== ""
        color: mb.edgeRole !== "" ? Qt.alpha(mb.edgeRole, 0.9) : "transparent"
        x: mb.inner === "right" ? mb.width - mb.hair : 0
        y: mb.inner === "bottom" ? mb.height - mb.hair : 0
        width: mb.vertical ? mb.hair : mb.width
        height: mb.vertical ? mb.height : mb.hair
    }
    Rectangle {
        visible: mb.edgeRole !== "" && mb.a >= 0.999 && !mb.vertical
        x: 0
        y: mb.inner === "bottom" ? mb.height : -3
        width: mb.width
        height: 3
        gradient: Gradient {
            GradientStop { position: mb.inner === "bottom" ? 0 : 1; color: Qt.rgba(0, 0, 0, 0.16) }
            GradientStop { position: mb.inner === "bottom" ? 1 : 0; color: Qt.rgba(0, 0, 0, 0) }
        }
    }
}
