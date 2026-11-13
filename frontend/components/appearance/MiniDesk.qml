import QtQuick
import "../../core"
import ".."

// The appearance menu's live preview (docs/ux/appearance-menu.md "The live preview"): the desktop in miniature — the
// picture, a bar and a small card in the colours in effect (the theme's tokens, so a previewed palette, scheme or style
// shows here as on the shell), or in `roles` (a picture's dry-run colours, `wallpaper.preview`) before it is set. The eye
// at its corner switches the section off (the menu writes `launcher.appearance_preview`).
Item {
    id: md
    property string picture: ""        // a file path; "" shows the theme's surface
    property var roles: null           // {accent, surface, on_surface, secondary} or null: the theme's own
    property string caption: ""
    signal hideRequested()

    function role(k, d) { return roles && roles[k] ? roles[k] : d }
    readonly property color accent: role("accent", Theme.accent)
    readonly property color surface: role("surface", Theme.surface)
    readonly property color ink: role("on_surface", Theme.fg)
    readonly property color second: role("secondary", Theme.color("color.secondary", Theme.dim))
    implicitHeight: Math.round(width * 5 / 16)
    Accessible.role: Accessible.Graphic
    Accessible.name: caption

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: Theme.nested(Theme.rLg, Theme.pad)
        color: Theme.containerHigh
        clip: true
        Image {
            id: pic
            anchors.fill: parent
            source: md.picture !== "" ? "file://" + String(md.picture).split("/").map(encodeURIComponent).join("/") : ""
            sourceSize.width: 480
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
            opacity: visible ? 1 : 0
            Behavior on opacity { enabled: Theme.springOn; NumberAnimation { duration: Theme.stdMs } }
        }
        // no picture: the theme's ground, so the bar and the card still read
        Rectangle {
            anchors.fill: parent
            visible: !pic.visible
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.darker(md.surface, 1.15) }
                GradientStop { position: 1; color: Qt.lighter(md.surface, 1.25) }
            }
        }
        // the bar
        Rectangle {
            x: 10; y: 8
            width: parent.width - 20; height: 14
            radius: 7
            color: Qt.alpha(md.surface, 0.92)
            Behavior on color { enabled: Theme.springOn; ColorAnimation { duration: Theme.stdMs } }
            Rectangle { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 22; height: 5; radius: 2.5; color: md.accent }
            Rectangle { anchors.centerIn: parent; width: 54; height: 8; radius: 4; color: Qt.alpha(md.ink, 0.85) }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Repeater { model: 3; Rectangle { width: 5; height: 5; radius: 2.5; color: md.second } }
            }
        }
        // a card
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 12
            y: 30
            width: Math.min(150, parent.width * 0.3); height: Math.max(36, parent.height - 76)
            radius: Math.min(12, Theme.rLg)
            color: Qt.alpha(md.surface, 0.95)
            Behavior on color { enabled: Theme.springOn; ColorAnimation { duration: Theme.stdMs } }
            Rectangle { x: 10; y: 10; width: parent.width * 0.42; height: 7; radius: 3.5; color: md.accent }
            Rectangle { x: 10; y: 24; width: parent.width - 20; height: 5; radius: 2.5; color: Qt.alpha(md.ink, 0.8) }
            Rectangle { x: 10; y: 34; width: parent.width * 0.6; height: 5; radius: 2.5; color: Qt.alpha(md.ink, 0.5) }
            Rectangle {
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8
                width: 30; height: 12; radius: 6; color: md.second
            }
        }
        // the caption, on a shade so it reads on any picture
        Rectangle {
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
            width: capText.implicitWidth + 12; height: capText.implicitHeight + 6
            radius: height / 2
            color: Qt.alpha("#000000", 0.45)
            visible: md.caption !== ""
            Text {
                id: capText
                anchors.centerIn: parent
                color: "#ffffff"
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                text: md.caption
            }
        }
        IconButton {
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 6
            icon: "visibility_off"
            glyph: "×"
            a11y: I18n.tr("appearance-menu.preview.hide")
            activeFocusOnTab: false
            onClicked: md.hideRequested()
        }
    }
}
