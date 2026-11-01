import QtQuick
import Quickshell
import "../../../core"
import "../.."

// FluentMenu (W53.3): Windows 11's Start as a start-menu skin (contract StartMenuBase): an Acrylic flyout with 8 px corners
// and the flyout's 1 px stroke, the search box and the app grid on its upper part (the launcher's own, laid in this
// room), and the footer band across the bottom — a shade darker, a hairline above it — with the user's avatar and name
// on the left (the launcher's session keys stand on its right, where 11 has its power button). The name is the login
// name (the session's environment: nothing else knows a name yet); the avatar its letter in a circle. Static: one paint
// per size (0 frames idle).
StartMenuBase {
    id: sm
    footerH: 64
    readonly property string user: String(Quickshell.env("USER") || "")
    readonly property real hair: Theme.crisp(1, Screen.devicePixelRatio)

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Theme.rLg
        color: Theme.panel
        border.width: sm.hair
        border.color: Theme.color("color.outline_variant", "#e5e5e5")
    }
    // The footer band: the flyout's ground a step deeper (11 lays SolidBackgroundFillColorBase at half over the
    // Acrylic), its lower corners following the flyout's.
    Rectangle {
        x: sm.hair
        y: parent.height - sm.footerH
        width: parent.width - 2 * sm.hair
        height: sm.footerH - sm.hair
        bottomLeftRadius: Math.max(0, Theme.rLg - sm.hair)
        bottomRightRadius: Math.max(0, Theme.rLg - sm.hair)
        color: Qt.alpha(Theme.surface, 0.55)
        Rectangle {
            width: parent.width
            height: sm.hair
            color: Theme.color("color.outline_variant", "#e5e5e5")
        }
        Row {
            x: 48
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            visible: sm.user !== ""
            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: Theme.color("color.accent_container", Theme.containerHigh)
                Text {
                    anchors.centerIn: parent
                    color: Theme.color("color.on_accent_container", Theme.fg)
                    font.pixelSize: Theme.fs + 1
                    font.weight: Theme.wMedium
                    font.family: Theme.fam(text, Theme.families)
                    text: sm.user.charAt(0).toUpperCase()
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.pixelSize: Theme.fsLabel
                font.family: Theme.fam(text, Theme.families)
                text: sm.user
            }
        }
    }
}
