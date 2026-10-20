import QtQuick
import qs.core
import qs.components

// One pin in the strip (docs/ux/webdock.md "Layout per edge"): the site's cached icon, or a letter tile when it has none;
// a dot when the page is loaded, a ring when it is the shown pin, a red mark when it stopped. The accessible name says
// what it is and its state in words, so no state rests on colour alone. Enter activates, the menu key and a right click
// open its menu (move, remove).
// W21 (K42): an app icon on a phone's home screen — a rounded-square keycap (Block) that sinks while pressed, the shown
// pin lit in `color.selected`; a letter tile's letter takes a data colour (by its id), never the accent.
Item {
    id: tile
    property var pin: ({})
    property int tileSize: 48
    property bool shown: false
    readonly property bool focusable: true
    readonly property bool isView: pin.kind === "view"
    readonly property bool iconUp: !isView && !!pin.icon && icon.status === Image.Ready
    readonly property string letter: String(pin.title || pin.id || "?").charAt(0).toUpperCase()
    // A data colour per pin (1..4), from its id: the same pin keeps its colour.
    readonly property int hue: {
        var t = String(pin.id || ""), h = 0
        for (var i = 0; i < t.length; i++) h = (h * 31 + t.charCodeAt(i)) % 997
        return h % 4 + 1
    }
    readonly property string stateWords: [
        isView ? I18n.tr("webdock.dock.kind.view") : I18n.tr("webdock.dock.kind.site"),
        shown ? I18n.tr("webdock.dock.state.shown") : "",
        pin.loaded === true ? I18n.tr("webdock.dock.state.loaded") : "",
        pin.error ? I18n.tr("webdock.dock.state.error") : ""
    ].filter(function (s) { return s !== "" }).join(", ")

    signal activated()
    signal menuRequested()
    // Tab and Shift+Tab are the strip's to route (into the card, or to the next tile): handled here, on the focused tile.
    signal tabbed(bool back)

    width: tileSize
    height: tileSize
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: String(pin.title || pin.id || "") + (stateWords !== "" ? ", " + stateWords : "")
    Keys.onReturnPressed: tile.activated()
    Keys.onEnterPressed: tile.activated()
    Keys.onMenuPressed: tile.menuRequested()
    Keys.onTabPressed: tile.tabbed(false)
    Keys.onBacktabPressed: tile.tabbed(true)

    Block {
        id: key
        x: Theme.shadowDy / 2
        width: tile.tileSize - Theme.shadowDy
        height: tile.tileSize
        radius: Math.round(width * 0.3)
        fill: tile.shown ? Theme.selected : (hover.hovered ? Qt.lighter(Theme.containerHigh, 1.04) : Theme.containerHigh)
        pressed: tap.pressed
        readonly property real innerW: width - 2 * inset
        readonly property real innerH: faceH - 2 * inset

        Image {
            id: icon
            anchors.centerIn: parent
            width: Math.round(key.innerW * 0.72)
            height: width
            source: tile.isView ? "" : String(tile.pin.icon || "")
            sourceSize.width: 64
            sourceSize.height: 64
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: tile.iconUp
        }
        Text {
            visible: !tile.iconUp
            anchors.centerIn: parent
            text: tile.letter
            color: tile.shown ? Theme.color("color.on_selected", Theme.fg) : Theme.dataColor(tile.hue)
            font.pixelSize: Theme.fsTitle + 2
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
        }
        // Loaded: a dot at the corner (the host reports `loaded`); stopped: a red dot at the other one.
        Rectangle {
            visible: tile.pin.loaded === true
            width: 6
            height: 6
            radius: 3
            color: Theme.accent
            x: key.innerW - width - 3
            y: key.innerH - height - 3
        }
        Rectangle {
            visible: !!tile.pin.error
            width: 7
            height: 7
            radius: 3.5
            color: Theme.error
            x: key.innerW - width - 2
            y: 2
        }
    }
    FocusRing {
        x: key.x
        width: key.width
        height: key.faceH
        shown: tile.activeFocus
        corner: key.radius
    }
    HoverHandler { id: hover }
    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: { tile.forceActiveFocus(); tile.activated() }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: { tile.forceActiveFocus(); tile.menuRequested() }
    }
}
