import QtQuick
import "../../../core"
import ".."

// GlassMenu (W53.2): the glass start-menu skin — Windows 7's Start menu (docs/ux/styles.md §3; the menu in the
// en.wikipedia "Windows 7 SP1 screenshot.png", read for layout only — it is scaled): a glass frame round everything (the
// look's glass role over the blur, a dark outer line and a light rim, 6 px corners), a white list pane inset in it with a
// soft inner shadow line, and a glass footer 44 px tall the session keys stand on (7's Shut down row). The launcher lays
// its search, rows and session keys inside (`footerH`); 7 had the search at the pane's foot — ours stays on top, the
// launcher's (an honest difference). Colours from roles (rule 4); static (one paint per size).
StartMenuBase {
    id: sm
    footerH: 44
    readonly property color glass: Theme.color("color.title", "#74b8fc")
    readonly property real a: Theme.tok("color.surface_alpha", 0.82)
    readonly property int frame: 8

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Qt.alpha(Qt.darker(sm.glass, 1.6), 0.55 * sm.a)
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.55)
    }
    Rectangle {
        anchors { fill: parent; margins: 1 }
        radius: 5
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.45)
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.22) }
            GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0.06) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.12) }
        }
    }
    // The list pane.
    Rectangle {
        x: sm.frame; y: sm.frame
        width: parent.width - 2 * sm.frame
        height: parent.height - sm.frame - sm.footerH
        radius: 3
        color: Theme.color("color.surface_container_lowest", "#ffffff")
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.4)
    }
}
