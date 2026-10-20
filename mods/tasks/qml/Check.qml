import QtQuick
import qs.core
import qs.components

// A task's checkbox (docs/ux/tasks.md, Design): a small Block that sinks while pressed and fills with the accent and a
// check when done. `fgDone` is the check's colour (named fg…: a property named on… reads back black). Inert (dimmed,
// no press) when `enabled` is false — a read-only file. The caller sends the action; this only draws and signals.
Item {
    id: c
    property bool checked: false
    property bool enabled: true
    property string a11y: ""
    property color fgDone: Theme.fgOnAccent
    signal toggled()

    implicitWidth: 22
    implicitHeight: 22 + Theme.shadowDy
    opacity: enabled ? 1 : 0.45

    activeFocusOnTab: false
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: c.checked
    Accessible.name: c.a11y

    Block {
        id: blk
        anchors.fill: parent
        radius: Theme.keycap ? 8 : 6
        ringScale: 0.34
        pressed: area.pressed && c.enabled
        fill: c.checked ? Theme.accent : (hover.hovered && c.enabled ? Theme.containerHigh : Theme.surface)
        flatBorder: c.checked ? Theme.accent : Theme.dim
        Icon {
            anchors.centerIn: parent
            visible: c.checked
            name: "check"
            glyph: "✓"
            size: 16
            color: c.fgDone
        }
    }
    HoverHandler { id: hover; cursorShape: c.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -5
        enabled: c.enabled
        onClicked: c.toggled()
    }
}
