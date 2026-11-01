import QtQuick
import "../../../core"
import ".."

// Shelf (W53.4): the Dock's body — Mac OS X 10.2–10.4's translucent white strip and macOS 11–14's floating vibrancy panel
// (docs/ux/styles.md §5, §6), from `[decor] dock.*` so one part serves both. A rounded `dock.radius` body in `dock.fill`
// (two roles: lighter away from the screen's edge), translucent — the look's material alpha, or ~60 % over a solid look
// (Tiger's shelf showed the desk through without a blur) — the look's ground pattern across it (Jaguar's pinstripes), a
// hairline dark rim outside and a light one inside (the glassy lip). With `dock.reflection` > 0 on a bottom dock the
// icons stand on a glass shelf: a bright line under them and below it their mirror image fading out — one
// ShaderEffectSource of the caller's icon list, redrawn only when the list changes (0 frames idle). Colours from roles
// (rule 4).
DockBase {
    id: sh
    readonly property var fills: Theme.decor("dock.fill", [])
    readonly property color upper: fills.length > 0 ? fills[0] : Theme.container
    readonly property color foot: fills.length > 1 ? fills[1] : upper
    readonly property real r: Theme.decor("dock.radius", -1) >= 0 ? Theme.decor("dock.radius", -1) : Theme.rLg + 4
    readonly property real themeA: Theme.tok("color.surface_alpha", 1)
    readonly property real a: themeA >= 0.999 ? 0.62 : themeA
    readonly property real refl: Theme.decor("dock.reflection", 0)
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)
    // Away from the screen's edge first.
    readonly property bool flip: edge === "top" || edge === "left"
    // The shelf's line under the icons (a bottom dock only), in this part's frame.
    readonly property bool shelf: refl > 0 && mirror !== null && edge === "bottom" && icon > 0
    readonly property real lineY: {
        if (!shelf) return 0
        var p = mirror.mapToItem(sh, 0, 0)
        return Math.round(p.y + sh.icon)
    }

    Rectangle {
        anchors.fill: parent
        radius: sh.r
        border.width: sh.hair
        border.color: Qt.rgba(0, 0, 0, Theme.darkScheme ? 0.55 : 0.22)
        gradient: Gradient {
            orientation: sh.vertical ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: sh.flip ? 1 : 0; color: Qt.alpha(sh.upper, sh.a) }
            GradientStop { position: sh.flip ? 0 : 1; color: Qt.alpha(sh.foot, sh.a) }
        }
        Pattern { anchors.fill: parent; radius: sh.r }
    }
    Rectangle {
        anchors { fill: parent; margins: sh.hair }
        radius: Math.max(0, sh.r - sh.hair)
        color: "transparent"
        border.width: sh.hair
        border.color: Qt.rgba(1, 1, 1, Theme.darkScheme ? 0.18 : 0.7)
    }
    // The glass shelf: the icons' mirror under the line, fading toward the screen's edge.
    Item {
        visible: sh.shelf
        x: 0
        y: sh.lineY
        width: sh.width
        height: Math.max(0, sh.height - sh.lineY - sh.hair)
        clip: true
        ShaderEffectSource {
            readonly property var p: sh.mirror ? sh.mirror.mapToItem(sh, 0, 0) : Qt.point(0, 0)
            x: p.x
            y: -sh.icon
            width: sh.mirror ? sh.mirror.width : 0
            height: sh.icon
            sourceItem: sh.shelf ? sh.mirror : null
            sourceRect: Qt.rect(0, 0, width, sh.icon)
            live: true
            hideSource: false
            opacity: sh.refl
            transform: Scale { yScale: -1; origin.y: sh.icon }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(sh.foot, sh.a * 0.25) }
                GradientStop { position: 1; color: Qt.alpha(sh.foot, sh.a) }
            }
        }
    }
    Rectangle {
        visible: sh.shelf
        x: sh.r / 2
        y: sh.lineY
        width: sh.width - sh.r
        height: sh.hair
        color: Qt.rgba(1, 1, 1, 0.85)
    }
}
