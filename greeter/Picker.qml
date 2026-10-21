import QtQuick
import "core"
import "components"

// A chip that opens a list above itself (the user and the session). Presentational: `options` [{label}] and `current`
// in, `chosen(index)` out. Keyboard: Return/Space opens; Up/Down move; Return picks; Escape closes. The list is made
// only while open (Ma). Tab is left to the view (one cycle over field, chips and power keys).
Item {
    id: p
    property var options: []
    property int current: 0
    property string icon: ""
    property string a11y: ""
    property bool enabled: true
    property bool open: false
    property int hl: 0
    signal chosen(int index)
    signal closed()

    readonly property string label: current >= 0 && current < options.length ? options[current].label : "—"
    implicitWidth: chip.implicitWidth
    implicitHeight: chip.implicitHeight
    Accessible.role: Accessible.ComboBox
    Accessible.name: p.a11y

    function show() { if (!enabled || options.length === 0) return; hl = Math.max(0, current); open = true; list.forceActiveFocus() }
    function hide() { open = false; p.closed() }

    Button {
        id: chip
        label: p.label
        icon: p.icon
        enabled: p.enabled
        activeFocusOnTab: false
        focus: true
        onClicked: p.open ? p.hide() : p.show()
    }
    function focusChip() { chip.forceActiveFocus() }
    readonly property bool chipFocused: chip.activeFocus

    Loader {
        active: p.open
        anchors { left: parent.left; bottom: parent.top; bottomMargin: Theme.gap }
        sourceComponent: Block {
            width: Math.max(220, col.implicitWidth + 2 * Theme.gap)
            height: col.implicitHeight + 2 * Theme.gap + Theme.shadowDy
            radius: Theme.rLg
            fill: Theme.container
            flatBorder: Theme.outline
            Column {
                id: col
                x: Theme.gap
                y: Theme.gap
                spacing: 2
                Repeater {
                    model: p.options
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: Math.max(204, t.implicitWidth + 2 * Theme.pad)
                        height: Theme.controlH
                        radius: Theme.rSm
                        color: index === p.hl ? Theme.selected : (ma.containsMouse ? Theme.containerHigh : "transparent")
                        Text {
                            id: t
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: Theme.pad }
                            text: row.modelData.label
                            color: row.index === p.hl ? Theme.fgOnSelected : Theme.fg
                            font.pixelSize: Theme.fs
                            font.weight: row.index === p.current ? Theme.wBold : Theme.wRegular
                            font.family: Theme.fam(text, Theme.families)
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            // Later: the row is destroyed when the list closes.
                            onClicked: { var i = row.index; Qt.callLater(function () { p.hide(); p.chosen(i) }) }
                        }
                    }
                }
            }
        }
    }
    // Keys of the open list (an invisible focus holder: the list itself lives in the Loader).
    Item {
        id: list
        Keys.onUpPressed: p.hl = (p.hl - 1 + p.options.length) % p.options.length
        Keys.onDownPressed: p.hl = (p.hl + 1) % p.options.length
        Keys.onReturnPressed: { p.hide(); p.chosen(p.hl) }
        Keys.onEnterPressed: { p.hide(); p.chosen(p.hl) }
        Keys.onSpacePressed: { p.hide(); p.chosen(p.hl) }
        Keys.onEscapePressed: { p.hide(); chip.forceActiveFocus() }
        // Tab and Shift+Tab close the list and move on from the chip (the view's cycle).
        Keys.onTabPressed: function (e) { p.open = false; chip.forceActiveFocus(); e.accepted = false }
        Keys.onBacktabPressed: function (e) { p.open = false; chip.forceActiveFocus(); e.accepted = false }
        // Focus moved elsewhere inside the window (a click on the field): close. The window losing the keyboard
        // (an output change, a keyboard unplugged) keeps it open.
        onActiveFocusChanged: if (!activeFocus && p.open && Window.active) p.open = false
    }
}
