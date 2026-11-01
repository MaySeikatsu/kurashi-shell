import QtQuick
import QtQuick.Effects
import "../../../core"
import ".."

// Popover (W53.4): the vibrancy start-menu skin — macOS 11–14's menus and Spotlight panel (docs/ux/styles.md §6): a
// translucent panel over the compositor's blur (the look's material: the theme's surface at its alpha), rounded
// `theme.shape.radius` + 2, a hairline light rim inside and a dark one outside, a wide soft shadow. The launcher keeps
// its search field on top (Spotlight's field), its rows and its session keys. Under reduce transparency the material is
// opaque and so is this. Colours from roles (rule 4); static (one paint per size).
StartMenuBase {
    id: sm
    readonly property real r: Theme.rLg
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)

    RectangularShadow {
        anchors.fill: parent
        radius: sm.r
        blur: 28
        offset.y: 8
        color: Qt.rgba(0, 0, 0, 0.28)
    }
    Rectangle {
        anchors.fill: parent
        radius: sm.r
        color: Theme.panel
        border.width: sm.hair
        border.color: Qt.rgba(0, 0, 0, Theme.darkScheme ? 0.6 : 0.18)
    }
    Rectangle {
        anchors { fill: parent; margins: sm.hair }
        radius: Math.max(0, sm.r - 1)
        color: "transparent"
        border.width: sm.hair
        border.color: Qt.rgba(1, 1, 1, Theme.darkScheme ? 0.16 : 0.5)
    }
}
