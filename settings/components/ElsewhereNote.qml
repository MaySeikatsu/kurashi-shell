import QtQuick
import "../core"

// W77 (K146; docs/ux/settings.md "In a sidebar"): what a host shows while the one content is in the other place — "Settings
// is open in its window" in the dock, "Settings is in the sidebar" in the window — and the key that brings it here (as the
// web dock's "Show here"). Takes the keyboard when it appears, so Return moves it at once.
Item {
    id: en
    property string text: ""
    property real radius: 0
    signal showHere()
    onVisibleChanged: if (visible) Qt.callLater(function () { if (en.visible) here.forceActiveFocus() })
    // (a click on the note never reaches what is under it)
    MouseArea { anchors.fill: parent }
    Rectangle {
        anchors.fill: parent
        radius: en.radius
        color: Theme.surface
    }
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Theme.pad, 360)
        spacing: Theme.gap * 2
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "settings"
            glyph: "⚙"
            size: Theme.fs * 2 + 8
            color: Theme.dim
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            color: Theme.fg
            font.pixelSize: Theme.fs + 1
            font.family: Theme.fam(text, Theme.families)
            text: en.text
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
        Button {
            id: here
            objectName: "show-here"
            anchors.horizontalCenter: parent.horizontalCenter
            primary: true
            label: I18n.tr("settings.dock.show_here")
            onClicked: en.showHere()
        }
    }
}
