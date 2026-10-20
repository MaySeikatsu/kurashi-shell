import QtQuick
import qs.core
import qs.components

// One pin in the strip (docs/ux/webdock.md "Layout per edge"): the site's cached icon, or a letter tile when it has none;
// a dot when the page is loaded, a ring when it is the shown pin, a red mark when it stopped. The accessible name says
// what it is and its state in words, so no state rests on colour alone. Enter activates, the menu key and a right click
// open its menu (move, remove).
Item {
    id: tile
    property var pin: ({})
    property int tileSize: 48
    property bool shown: false
    readonly property bool focusable: true
    readonly property bool isView: pin.kind === "view"
    readonly property bool iconUp: !isView && !!pin.icon && icon.status === Image.Ready
    readonly property string letter: String(pin.title || pin.id || "?").charAt(0).toUpperCase()
    readonly property string stateWords: [
        isView ? I18n.tr("webdock.dock.kind.view") : I18n.tr("webdock.dock.kind.site"),
        shown ? I18n.tr("webdock.dock.state.shown") : "",
        pin.loaded === true ? I18n.tr("webdock.dock.state.loaded") : "",
        pin.error ? I18n.tr("webdock.dock.state.error") : ""
    ].filter(function (s) { return s !== "" }).join(", ")

    signal activated()
    signal menuRequested()

    width: tileSize
    height: tileSize
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: String(pin.title || pin.id || "") + (stateWords !== "" ? ", " + stateWords : "")
    Keys.onReturnPressed: tile.activated()
    Keys.onEnterPressed: tile.activated()
    Keys.onMenuPressed: tile.menuRequested()

    Rectangle {
        anchors.fill: parent
        radius: Theme.rSm
        color: hover.hovered || tile.shown ? Theme.containerHigh : "transparent"
        border.width: tile.shown ? 2 : 0
        border.color: Theme.accent
    }
    Image {
        id: icon
        anchors.centerIn: parent
        width: tile.tileSize - 16
        height: width
        source: tile.isView ? "" : String(tile.pin.icon || "")
        sourceSize.width: 64
        sourceSize.height: 64
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: tile.iconUp
    }
    Rectangle {
        visible: !tile.iconUp
        anchors.centerIn: parent
        width: tile.tileSize - 12
        height: width
        radius: Theme.rSm
        color: Qt.alpha(Theme.accent, 0.3)
        Text {
            anchors.centerIn: parent
            text: tile.letter
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
        }
    }
    // Loaded: a dot at the corner (the host reports `loaded`); stopped: a red dot at the other one.
    Rectangle {
        visible: tile.pin.loaded === true
        width: 6
        height: 6
        radius: 3
        color: Theme.accent
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 4
        anchors.bottomMargin: 4
    }
    Rectangle {
        visible: !!tile.pin.error
        width: 6
        height: 6
        radius: 3
        color: Theme.error
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 4
        anchors.topMargin: 4
    }
    FocusRing {
        anchors.fill: parent
        shown: tile.activeFocus
        corner: Theme.rSm
    }
    HoverHandler { id: hover }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: { tile.forceActiveFocus(); tile.activated() }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: { tile.forceActiveFocus(); tile.menuRequested() }
    }
}
