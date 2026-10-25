import QtQuick
import qs.core
import qs.components

// The web dock's icon strip (docs/ux/webdock.md "Layout per edge"): the pins in their order, a divider where the kind
// changes, then the dock's own controls at the end (pin the dock, add, settings). Vertical on a side edge, horizontal on
// top and bottom. It scrolls when it is longer than the output and never shrinks an icon. Keys: the along arrows move
// between the tiles, Enter activates one, Space toggles the dock's pin, Escape steps back, Tab goes to the card.
// `rows` is what dock.qml builds: [{kind: "pin", pin} | {kind: "divider"} | {kind: "ctl", ctl: "pin"|"add"|"settings"}].
Flickable {
    id: strip
    property bool vertical: true
    property int thick: 56              // geometry.strip: the strip's thickness across the edge
    property var rows: []
    property string shownId: ""
    property bool pinned: false
    property bool pinForced: false      // set by the configuration: the dock's pin toggle is inert
    property string pinForcedBy: ""     // the source that forces it (I91), named in the toggle's accessible name
    property bool panelOpen: false      // a card or a panel is up: Tab goes to it
    readonly property int tile: thick - 8
    // The length the content takes along the edge (dock.qml sizes the strip to it, up to the output).
    readonly property real contentLen: vertical ? grid.height + 8 : grid.width + 8

    signal pinSelected(string pin)
    signal pinMenu(string pin)
    signal pinToggled()
    signal addPressed()
    signal settingsPressed()
    signal backPressed()
    signal tabPressed()

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: vertical ? width : grid.width + 8
    contentHeight: vertical ? grid.height + 8 : height

    // The tile at `i` when it takes focus (pins and controls), else null.
    function focusable(i) {
        var it = rep.itemAt(i)
        return it && it.item && it.item.focusable === true ? it.item : null
    }
    // Moves focus `d` steps (+1 or -1) to the next focusable tile; from nothing it takes the first or the last.
    function step(d) {
        var from = -1
        for (var i = 0; i < rep.count; i++) {
            var f = focusable(i)
            if (f && f.activeFocus) from = i
        }
        var j = from < 0 ? (d > 0 ? 0 : rep.count - 1) : from + d
        while (j >= 0 && j < rep.count) {
            var g = focusable(j)
            if (g) { g.forceActiveFocus(); return }
            j += d
        }
    }
    function focusFirst() {
        for (var i = 0; i < rep.count; i++) {
            var f = focusable(i)
            if (f) { f.forceActiveFocus(); return }
        }
    }
    // Focus goes to the tile with this id: a pin's id, or a control's name ("pin", "add", "settings").
    function focusId(id) {
        for (var i = 0; i < rep.count; i++) {
            var f = focusable(i)
            if (f && ((f.pin && f.pin.id === id) || f.name === id)) { f.forceActiveFocus(); return }
        }
    }

    // Tab from a tile: into the card when one is up, else on to the next tile; Shift+Tab steps back.
    function tabFrom(back) {
        if (!back && strip.panelOpen) strip.tabPressed()
        else strip.step(back ? -1 : 1)
    }

    Keys.onUpPressed: if (vertical) strip.step(-1)
    Keys.onDownPressed: if (vertical) strip.step(1)
    Keys.onLeftPressed: if (!vertical) strip.step(-1)
    Keys.onRightPressed: if (!vertical) strip.step(1)
    Keys.onSpacePressed: strip.pinToggled()
    Keys.onEscapePressed: strip.backPressed()
    Keys.onTabPressed: strip.tabPressed()

    Grid {
        id: grid
        x: 4
        y: 4
        spacing: 4
        columns: strip.vertical ? 1 : 0
        rows: strip.vertical ? 0 : 1
        flow: strip.vertical ? Grid.LeftToRight : Grid.TopToBottom

        Repeater {
            id: rep
            model: strip.rows
            delegate: Loader {
                id: cell
                required property var modelData
                readonly property string kind: modelData.kind
                sourceComponent: kind === "pin" ? pinC : (kind === "divider" ? divC : ctlC)

                Component {
                    id: pinC
                    PinTile {
                        pin: cell.modelData.pin
                        tileSize: strip.tile
                        shown: strip.shownId === cell.modelData.pin.id
                        onActivated: strip.pinSelected(cell.modelData.pin.id)
                        onMenuRequested: strip.pinMenu(cell.modelData.pin.id)
                        onTabbed: back => strip.tabFrom(back)
                    }
                }
                Component {
                    id: divC
                    Item {
                        width: strip.vertical ? strip.tile : 9
                        height: strip.vertical ? 9 : strip.tile
                        Rectangle {
                            anchors.centerIn: parent
                            width: strip.vertical ? parent.width - 16 : 1
                            height: strip.vertical ? 1 : parent.height - 16
                            color: Theme.outline
                        }
                    }
                }
                // A control is the whole tile (48 px), a target as large as a pin's: a tap, Enter or Space presses it.
                Component {
                    id: ctlC
                    Item {
                        id: ctl
                        width: strip.tile
                        height: strip.tile
                        readonly property string name: cell.modelData.ctl
                        readonly property bool isPin: name === "pin"
                        readonly property bool lit: isPin && strip.pinned
                        readonly property bool live: !(isPin && strip.pinForced)
                        readonly property bool focusable: true
                        readonly property string glyph: isPin ? "◧" : (name === "add" ? "+" : "⚙")
                        readonly property string icon: isPin ? "push_pin" : (name === "add" ? "add" : "settings")
                        readonly property string a11yName: isPin
                            ? I18n.tr(lit ? "webdock.pin.undock" : "webdock.pin.dock")
                                + (strip.pinForced ? ". " + I18n.tr("webdock.dock.forced") + " " + strip.pinForcedBy : "")
                            : (name === "add" ? I18n.tr("webdock.dock.add") : I18n.tr("webdock.dock.settings"))

                        function press() {
                            if (!ctl.live) return
                            if (ctl.isPin) strip.pinToggled()
                            else if (ctl.name === "add") strip.addPressed()
                            else strip.settingsPressed()
                        }
                        activeFocusOnTab: live
                        Keys.onReturnPressed: ctl.press()
                        Keys.onEnterPressed: ctl.press()
                        Keys.onSpacePressed: ctl.press()
                        Keys.onTabPressed: strip.tabFrom(false)
                        Keys.onBacktabPressed: strip.tabFrom(true)
                        Accessible.role: Accessible.Button
                        Accessible.name: ctl.a11yName

                        // A round key (K42): the dock's own controls, quieter than the pins' app icons.
                        Block {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 6
                            width: ctl.width - 12
                            height: ctl.width - 12 + Theme.shadowDy
                            radius: Theme.rFull
                            ringScale: 0.5
                            softScale: 0.4
                            fill: ctl.lit ? Theme.selected : (hov.hovered ? Theme.containerHigh : Theme.container)
                            pressed: ctlTap.pressed && ctl.live
                            opacity: ctl.live ? 1 : 0.5
                            Icon {
                                anchors.centerIn: parent
                                name: ctl.icon
                                glyph: ctl.glyph
                                filled: ctl.lit
                                size: 18
                                color: ctl.lit ? Theme.color("color.on_selected", Theme.fg) : Theme.fg
                            }
                        }
                        HoverHandler { id: hov }
                        TapHandler {
                            id: ctlTap
                            onTapped: ctl.press()
                        }
                        FocusRing {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 6
                            width: ctl.width - 12
                            height: ctl.width - 12
                            shown: ctl.activeFocus
                            corner: width / 2
                        }
                    }
                }
            }
        }
    }
}
