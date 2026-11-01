import QtQuick
import Quickshell
import "../../../core"
import ".."

// GlossMenu (W53.2): the glossy start-menu skin — Windows XP's Start menu (docs/ux/styles.md §2, measured on
// guidebookgallery.org's pics/gui/desktop/firstrun/winxppro-2-1.png, the menu x 0–379, y 92–569): a blue header 64 px
// tall (`title`'s body falling to its glow, a light line under its top edge) with the user's picture in a white frame and
// the name in bold white, the orange rule (`tertiary`, 2 px, brightest in the middle) under it, a white body framed by
// 1 px of deep blue, and a blue footer 41 px tall (the glow rising to the body colour) under the session keys; the top
// corners rounded 6 px. The launcher lays its search, rows and session keys inside (`headerH`, `footerH`); the body's
// right part is XP's pale-blue places column, the rows' own ground where the launcher draws them. Colours from roles
// (rule 4); static (one paint per size).
StartMenuBase {
    id: sm
    headerH: 64
    footerH: 41
    readonly property color body: Theme.color("color.title", "#0055e5")
    readonly property color glow: Theme.color("color.title_end", "#026afe")
    readonly property color rim: Qt.darker(body, 1.35)
    readonly property string who: String(Quickshell.env("USER") || "")
    readonly property real r: 6

    Rectangle {
        anchors.fill: parent
        topLeftRadius: sm.r
        topRightRadius: sm.r
        color: sm.rim
    }
    // The body: white, the places column's pale blue on the right third.
    Rectangle {
        x: 1; y: sm.headerH
        width: parent.width - 2; height: parent.height - sm.headerH - sm.footerH
        color: Theme.color("color.surface_container_lowest", "#ffffff")
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: Math.round(parent.width * 0.47)
            color: Qt.tint(Theme.color("color.surface_container_lowest", "#ffffff"), Qt.alpha(sm.glow, 0.18))
            Rectangle { width: 1; height: parent.height; color: Qt.tint(Theme.color("color.surface_container_lowest", "#ffffff"), Qt.alpha(sm.glow, 0.4)) }
        }
    }
    // The header.
    Rectangle {
        x: 1; y: 1
        width: parent.width - 2; height: sm.headerH - 1
        topLeftRadius: sm.r - 1
        topRightRadius: sm.r - 1
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(sm.body, 1.1) }
            GradientStop { position: 0.04; color: Qt.tint(sm.glow, Qt.rgba(1, 1, 1, 0.45)) }
            GradientStop { position: 0.1; color: Qt.darker(sm.body, 1.05) }
            GradientStop { position: 0.3; color: Qt.darker(sm.body, 1.12) }
            GradientStop { position: 1; color: Qt.tint(sm.glow, Qt.rgba(1, 1, 1, 0.2)) }
        }
    }
    Row {
        x: 7; y: 7
        spacing: 9
        Rectangle {
            width: 50; height: 50
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.92)
            Rectangle {
                anchors { fill: parent; margins: 2 }
                radius: 2
                color: Qt.darker(sm.body, 1.3)
                clip: true
                Text {
                    anchors.centerIn: parent
                    visible: pic.status !== Image.Ready
                    text: sm.who.charAt(0).toUpperCase()
                    color: Qt.rgba(1, 1, 1, 1)
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                Image {
                    id: pic
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 46
                    sourceSize.height: 46
                    source: Quickshell.env("HOME") ? "file://" + Quickshell.env("HOME") + "/.face" : ""
                }
            }
        }
        Item {
            width: name.implicitWidth
            height: 50
            Text {
                x: 1; y: 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 1
                text: name.text
                font: name.font
                color: Qt.darker(sm.body, 2.2)
            }
            Text {
                id: name
                anchors.verticalCenter: parent.verticalCenter
                text: sm.who
                color: Qt.rgba(1, 1, 1, 1)
                font.family: Theme.tok("font.title", "") || Theme.families[0]
                font.pixelSize: 16
                font.weight: Font.Bold
            }
        }
    }
    // The orange rule.
    Rectangle {
        x: 1; y: sm.headerH - 2
        width: parent.width - 2; height: 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(Theme.tertiary, 0.25) }
            GradientStop { position: 0.5; color: Qt.lighter(Theme.tertiary, 1.15) }
            GradientStop { position: 1; color: Qt.alpha(Theme.tertiary, 0.25) }
        }
    }
    // The footer.
    Rectangle {
        x: 1
        y: parent.height - sm.footerH
        width: parent.width - 2; height: sm.footerH - 1
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.tint(sm.glow, Qt.rgba(1, 1, 1, 0.25)) }
            GradientStop { position: 1; color: Qt.darker(sm.body, 1.1) }
        }
    }
}
