import QtQuick
import Quickshell
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
    // Tab follows the focus chain in tree order (I90): the header's size and collapse, then the view's own controls. The
    // header's explicit Tab links used to close the loop at the header, so a view's controls were never reached.
    readonly property bool debugLog: Quickshell.env("KURASHI_WEBDOCK_DEBUG") === "1"   // test-only: the focus, logged
    // Test-only (KURASHI_WEBDOCK_DEBUG=1): each focus change of the window, by the focused control's name (event-driven).
    Connections {
        target: card.debugLog ? card.Window : null
        function onActiveFocusItemChanged() {
            var f = card.Window.activeFocusItem
            console.log("webdock-debug focus", f ? (f.label || f.a11y || "") : "none")
        }
    }

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
        // The view keeps clear of the card's edges in both looks (I90): the large card's body had none, so the view's
        // content touched the edge while the header's title sat inset. The sides line up with the title's inset.
        anchors.topMargin: Theme.gap
        anchors.bottomMargin: Theme.gap
        anchors.leftMargin: Theme.pad
        anchors.rightMargin: Theme.pad
    }
}
