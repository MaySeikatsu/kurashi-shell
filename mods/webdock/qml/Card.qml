import QtQuick
import Quickshell
import qs.core
import qs.components
import "frames"

// The frame of the dock's card for a view pin, a cold web pin and the empty dock: the look of the web host's card
// (mods/webdock/host/WebCard.qml, so the two line up): a 36 px header with the title, the phone/large size and collapse,
// and the body below. The body is the default child. Escape on the header or the body steps back (`webdock.back`).
// W21 (K42): the phone size is the host's phone: the status row, the header under it, the body on the screen, the home
// indicator. W69 (I468; docs/ux/webdock.md "Page styles"): the card wears the dock's page style (`style`), with the
// host's own frames (mods/webdock/qml/frames links mods/webdock/host/frames): the phone, a tablet lying sideways in the
// large size (DeviceFrame); one half of an opened spiral notebook, bound on the dock's side (`edge`); or plain, the
// dock's card. So a cold card and the page that replaces it wear the same frame.
Item {
    id: card
    property string title: ""
    property bool large: false
    property bool sizable: true
    property string style: "phone"
    property string edge: "right"
    default property alias body: bodySlot.data
    signal sizeChosen(string size)
    signal collapse()
    signal escaped()

    readonly property bool isNotebook: style === "notebook"
    readonly property bool isPlain: style === "plain"
    readonly property bool isPhone: !isNotebook && !isPlain
    readonly property bool sideways: edge === "left" || edge === "right"
    // The phone's title pill (the tablet, the notebook and the plain card have a plain title).
    readonly property bool phoneLook: isPhone && !large
    // The status row's time (svc.clock, watched while the device is up).
    readonly property var clock: Store.docs["svc.clock"] || ({})
    Watch { doc: "svc.clock"; active: card.isPhone }
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
    readonly property Component roundBox: Component { RoundBox {} }
    readonly property Component relief: Component { Relief {} }

    // ---- the frame under the content ----
    DeviceFrame {
        id: phone
        visible: card.isPhone
        anchors.fill: parent
        theme: Theme
        wide: card.large ? 1 : 0
        box: card.roundBox
        relief: card.relief
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
    NotebookGeom {
        id: nb
        width: card.width
        height: card.height
        edge: card.edge
    }
    Loader {
        anchors.fill: parent
        active: card.isNotebook
        sourceComponent: NotebookBack { theme: Theme; geom: nb; box: card.roundBox }
    }
    Loader {
        x: nb.sheet.x
        y: nb.sheet.y
        width: nb.sheet.width
        height: nb.sheet.height
        active: card.isNotebook
        sourceComponent: NotebookSheet { theme: Theme; geom: nb; headY: screen.y - nb.sheet.y + head.height }
    }
    RoundBox {
        visible: card.isPlain
        anchors.fill: parent
        radius: Theme.rLg
        color: Theme.container
        border.width: Theme.outlineW
        border.color: Theme.outlineColor
    }

    // The header and the body: on the device's screen under its status row and over its home indicator, on the
    // notebook's sheet inside its margins (more on the bound side), or on the whole plain card.
    Item {
        id: screen
        readonly property real bindM: 20
        readonly property real freeM: 10
        x: card.isPhone ? phone.screen.x : card.isNotebook ? nb.sheet.x + (card.edge === "left" ? bindM : freeM) : 0
        y: card.isPhone ? phone.screen.y + phone.statusH : card.isNotebook ? nb.sheet.y + (card.edge === "top" ? bindM : 8) : 0
        width: card.isPhone ? phone.screen.width
            : card.isNotebook ? nb.sheet.width - (card.sideways ? bindM + freeM : 2 * freeM) : card.width
        height: card.isPhone ? phone.screen.height - phone.statusH - phone.homeH
            : card.isNotebook ? nb.sheet.height - (card.sideways ? 8 + 14 : bindM + (card.edge === "top" ? 14 : 8)) : card.height
        clip: !card.isPlain
    }

    Item {
        id: head
        parent: screen
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: card.isPhone ? 6 : 0
        anchors.rightMargin: card.isPhone ? 6 : 0
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
            anchors.leftMargin: card.phoneLook ? 18 : (card.isNotebook ? 4 : Theme.pad)
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
        // The view keeps clear of the card's edges in every style (I90): the sides line up with the title's inset.
        anchors.topMargin: Theme.gap
        anchors.bottomMargin: Theme.gap
        anchors.leftMargin: card.isNotebook ? 4 : Theme.pad
        anchors.rightMargin: card.isNotebook ? 4 : Theme.pad
    }

    // The notebook's coil, over the sheet.
    Loader {
        anchors.fill: parent
        active: card.isNotebook
        sourceComponent: NotebookWire { theme: Theme; geom: nb }
    }
}
