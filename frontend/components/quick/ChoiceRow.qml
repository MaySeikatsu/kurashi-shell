import QtQuick
import "../../core"
import ".."

// A row of a list in a page (W13): an optional radio mark, the title, and a state line under it (or "Connecting…" while
// its request is pending), with an optional strength (`bars`, 0..4). Enter, Space or a click activates it, unless it is
// `inert` (the active choice, a single device). Keyboard focus draws the ring; the radio is the value in effect.
Item {
    id: row
    implicitHeight: Math.max(Theme.controlH, labels.implicitHeight + 4)
    property string title: ""
    property string sub: ""
    property bool radio: false
    property bool checked: false
    property int bars: -1               // -1: no strength; else 0..4 lit bars
    property bool pending: false
    property string pendingText: ""
    property bool inert: false
    signal activated()

    function press() { if (!inert && !pending) row.activated() }

    activeFocusOnTab: !inert
    Keys.onReturnPressed: row.press()
    Keys.onEnterPressed: row.press()
    Keys.onSpacePressed: row.press()
    Accessible.role: row.radio ? Accessible.RadioButton : Accessible.Button
    Accessible.name: row.title
    Accessible.description: row.pending ? row.pendingText : row.sub
    Accessible.checked: row.checked

    Rectangle {
        id: mark
        visible: row.radio
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        radius: 8
        color: "transparent"
        border.width: 2
        border.color: row.checked ? Theme.accent : Theme.dim
        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: Theme.accent
            visible: row.checked
        }
    }
    Column {
        id: labels
        x: row.radio ? mark.width + Theme.gap : 0
        width: row.width - x - (strength.visible ? strength.width + Theme.gap : 0)
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            elide: Text.ElideRight
            color: Theme.fg
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: row.title
        }
        Text {
            width: parent.width
            visible: text !== ""
            elide: Text.ElideRight
            color: row.pending ? Theme.fg : Theme.dim
            font.pixelSize: Theme.fsCaption
            font.family: Theme.fam(text, Theme.families)
            text: row.pending ? row.pendingText : row.sub
        }
    }
    // Signal strength: four steps, the lit ones in the foreground colour (the level is also in the state line's words).
    Row {
        id: strength
        visible: row.bars >= 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        height: 13
        Repeater {
            model: 4
            Item {
                required property int index
                width: 3
                height: strength.height
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 4 + parent.index * 3
                    radius: 1
                    color: parent.index < row.bars ? Theme.fg : Theme.outline
                }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: !row.inert
        onClicked: row.press()
    }
    FocusRing {
        anchors.fill: parent
        shown: row.activeFocus
        corner: Theme.rSm
    }
}
