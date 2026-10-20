import QtQuick
import qs.core
import qs.components

// The frame of the dock's card for a view pin, a cold web pin and the empty dock: the look of the web host's card
// (mods/webdock/host/WebCard.qml, so the two line up): a 36 px header with the title, the phone/large size and collapse,
// and the body below. The body is the default child. Escape on the header or the body steps back (`webdock.back`).
Rectangle {
    id: card
    property string title: ""
    property bool large: false
    property bool sizable: true
    default property alias body: bodySlot.data
    signal sizeChosen(string size)
    signal collapse()
    signal escaped()

    radius: Theme.rLg
    color: Theme.container
    clip: true
    activeFocusOnTab: true
    Keys.onEscapePressed: card.escaped()
    // Tab walks the header explicitly (size, collapse, and back to the card), not by the order of the focus chain.
    KeyNavigation.tab: card.sizable ? sizeBtn : collapseBtn

    Item {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36

        Row {
            id: buttons
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Button {
                id: sizeBtn
                visible: card.sizable
                anchors.verticalCenter: parent.verticalCenter
                label: card.large ? I18n.tr("webdock.size.phone") : I18n.tr("webdock.size.large")
                onClicked: card.sizeChosen(card.large ? "phone" : "large")
                KeyNavigation.tab: collapseBtn
            }
            IconButton {
                id: collapseBtn
                anchors.verticalCenter: parent.verticalCenter
                glyph: "×"
                a11y: I18n.tr("webdock.nav.collapse")
                onClicked: card.collapse()
                KeyNavigation.tab: card
            }
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.pad
            anchors.right: buttons.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            text: card.title
            color: Theme.fg
            elide: Text.ElideRight
            font.pixelSize: Theme.fsLabel
            font.family: Theme.fam(text, Theme.families)
        }
    }
    Item {
        id: bodySlot
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
}
