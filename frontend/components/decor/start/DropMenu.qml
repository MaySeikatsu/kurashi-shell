import QtQuick
import QtQuick.Effects
import "../../../core"
import ".."

// DropMenu (W53.4): the pull-down start-menu skin — Mac OS X 10.2–10.4's menus (docs/ux/styles.md §5): the menu hangs
// from the bar with its top edge square against it and its far corners rounded 5 px, white a touch translucent, the
// look's ground pattern (Jaguar's pinstripes) faint across it, a soft shadow round it; no header, no band, no footer of
// its own (the launcher keeps the search on top, its rows and its session keys). Our mark's menu opens the launcher in
// it, as the Apple menu and Spotlight's results did. Colours from roles (rule 4); static (one paint per size).
StartMenuBase {
    id: sm
    readonly property bool fromTop: edge === "top"
    readonly property color ground: Theme.color("color.surface_container_lowest", "#ffffff")

    RectangularShadow {
        anchors.fill: parent
        anchors.topMargin: sm.fromTop ? 4 : 0
        anchors.bottomMargin: sm.fromTop ? 0 : 4
        radius: 5
        blur: 14
        offset.y: sm.fromTop ? 4 : -2
        color: Qt.rgba(0, 0, 0, 0.32)
    }
    Rectangle {
        anchors.fill: parent
        topLeftRadius: sm.fromTop ? 0 : 5
        topRightRadius: sm.fromTop ? 0 : 5
        bottomLeftRadius: sm.fromTop ? 5 : 0
        bottomRightRadius: sm.fromTop ? 5 : 0
        color: Qt.alpha(sm.ground, 0.96)
        border.width: 1
        border.color: Qt.alpha(Theme.outline, 0.45)
        Pattern { anchors.fill: parent; radius: 5 }
    }
}
