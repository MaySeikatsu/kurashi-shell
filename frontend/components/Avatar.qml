import QtQuick
import Quickshell.Widgets
import "../core"

// The session's user as a round key (I108, K163): the account's picture when it has one, else the first letter of the
// name, else a person. From the `daemon` document's `user` (the daemon reads the account; the frontend reads nothing of
// the session itself). `name` is what to call the user: the full name, else the login, else "".
Block {
    id: av
    Watch { doc: "daemon" }
    readonly property var user: (Store.docs["daemon"] || ({})).user || ({})
    readonly property string name: String(user.full_name || user.name || "")
    readonly property string picture: user.icon ? "file://" + user.icon : ""
    width: 44
    height: 44 + Theme.shadowDy
    radius: Theme.rFull
    fill: Theme.selected
    ClippingRectangle {
        visible: face.status === Image.Ready
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.shadowDy / 2
        width: av.width - 4
        height: width
        radius: width / 2
        color: "transparent"
        Image {
            id: face
            anchors.fill: parent
            source: av.picture
            sourceSize: Qt.size(2 * av.width, 2 * av.width)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }
    Label {
        visible: face.status !== Image.Ready && av.name !== ""
        anchors.centerIn: parent
        color: Theme.color("color.on_selected", Theme.fg)
        font.pixelSize: Theme.fsTitle + 4
        font.weight: Theme.wBold
        text: av.name.charAt(0).toUpperCase()
        TextFx { title: true }
    }
    Icon {
        visible: face.status !== Image.Ready && av.name === ""
        anchors.centerIn: parent
        name: "person"
        glyph: "◡"
        filled: true
        size: 24
        color: Theme.color("color.on_selected", Theme.fg)
    }
}
