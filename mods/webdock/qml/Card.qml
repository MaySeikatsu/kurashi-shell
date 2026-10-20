import QtQuick
import qs.core
import qs.components
import qs.components.phone

// The frame of the dock's card for a view pin, a cold web pin and the empty dock: the look of the web host's card
// (mods/webdock/host/WebCard.qml, so the two line up): a 36 px header with the title, the phone/large size and collapse,
// and the body below. The body is the default child. Escape on the header or the body steps back (`webdock.back`).
// W21 (K42): the phone size is the host's phone (PhoneFrame): the status row, the header under it, the body on the screen,
// the home indicator; the large size stays a plain card.
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
    color: phoneLook ? "transparent" : Theme.container
    clip: !phoneLook
    readonly property bool phoneLook: !large
    // The status row's time (svc.clock, watched while the card is up).
    readonly property var clock: Store.docs["svc.clock"] || ({})
    Watch { doc: "svc.clock"; active: card.phoneLook }
    activeFocusOnTab: true
    Keys.onEscapePressed: card.escaped()
    // Tab walks the header explicitly (size, collapse, and back to the card), not by the order of the focus chain.
    KeyNavigation.tab: card.sizable ? sizeBtn : collapseBtn

    PhoneFrame {
        id: phone
        visible: card.phoneLook
        anchors.fill: parent
        theme: Theme
        statusLeft: Text {
            height: phone.statusH
            verticalAlignment: Text.AlignVCenter
            text: card.clock.hh !== undefined ? card.clock.hh + ":" + card.clock.mm : ""
            color: Theme.fg
            font.pixelSize: Theme.fsLabel
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
        }
    }
    // Phone: the header and the body on the phone's screen, under its status row and over its home indicator.
    Item {
        id: screen
        x: card.phoneLook ? phone.screen.x : 0
        y: card.phoneLook ? phone.screen.y + phone.statusH : 0
        width: card.phoneLook ? phone.screen.width : card.width
        height: card.phoneLook ? phone.area.height : card.height
        clip: card.phoneLook
    }

    Item {
        id: head
        parent: screen
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: card.phoneLook ? 6 : 0
        anchors.rightMargin: card.phoneLook ? 6 : 0
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
        // Phone: the title in a pill, as the host's phone has it (a keycap block: no press, so no sinking).
        Block {
            id: titlePill
            visible: card.phoneLook
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: buttons.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            height: 30 + Theme.shadowDy
            radius: Theme.rFull
            ringScale: 0
            fill: Theme.containerHigh
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: card.phoneLook ? 18 : Theme.pad
            anchors.right: buttons.left
            anchors.rightMargin: card.phoneLook ? Theme.gap + 14 : Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: card.phoneLook ? -Theme.shadowDy / 2 : 0
            horizontalAlignment: card.phoneLook ? Text.AlignHCenter : Text.AlignLeft
            text: card.title
            color: Theme.fg
            elide: Text.ElideRight
            font.pixelSize: Theme.fsLabel
            font.weight: card.phoneLook ? Theme.wBold : Theme.wRegular
            font.family: Theme.fam(text, Theme.families)
        }
    }
    Item {
        id: bodySlot
        parent: screen
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // Phone: the view keeps clear of the screen's straight edges.
        anchors.topMargin: card.phoneLook ? Theme.gap : 0
        anchors.leftMargin: card.phoneLook ? Theme.pad : 0
        anchors.rightMargin: card.phoneLook ? Theme.pad : 0
    }
}
