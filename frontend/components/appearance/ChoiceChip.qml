import QtQuick
import "../../core"
import ".."

// A choice in an appearance pane: one option of a radio group (`check: false`) or one item of a list (`check: true`).
// The chosen one sits on the `selected` tone in bold (a mark, not colour alone: a check for a list). The group's row
// holds the focus; `ringed` draws the ring round the option the keys act on.
Rectangle {
    id: chip
    property string label: ""
    property bool chosen: false
    property bool check: false
    property bool ringed: false
    property bool enabled: true
    signal picked()

    implicitWidth: Math.max(56, row.implicitWidth + 2 * Theme.pad)
    implicitHeight: 30
    width: implicitWidth
    height: implicitHeight
    radius: Math.min(height / 2, Theme.rFull)
    color: chosen ? Theme.selected : (hover.hovered && enabled ? Theme.containerHigh : "transparent")
    border.width: chosen ? 0 : 1
    border.color: Theme.outline
    opacity: enabled ? 1 : 0.5
    Behavior on color { enabled: Theme.springOn; ColorAnimation { duration: Theme.quickMs } }
    Accessible.role: check ? Accessible.CheckBox : Accessible.RadioButton
    Accessible.name: label
    Accessible.checkable: true
    Accessible.checked: chosen

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Icon {
            visible: chip.check && chip.chosen
            anchors.verticalCenter: parent.verticalCenter
            name: "check"
            glyph: "✓"
            size: Theme.fs
            color: Theme.fgOnSelected
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: chip.chosen ? Theme.fgOnSelected : Theme.fg
            font.pixelSize: Theme.fsLabel
            font.weight: chip.chosen ? Theme.wBold : Theme.wRegular
            font.family: Theme.fam(text, Theme.families)
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            text: chip.label
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: chip.enabled; onTapped: chip.picked() }
    FocusRing { anchors.fill: parent; corner: chip.radius; shown: chip.ringed }
}
