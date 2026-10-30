import QtQuick
import "../../core"
import ".."

// The top row of a drill-down page (W13; W21: a round back key and the title). The whole header is the Back control: Enter, Space or a click go back
// (Esc and Left are handled by the card, QuickPanel). It is the first Tab stop of every page.
Item {
    id: hd
    implicitWidth: head.implicitWidth + 2 * Theme.gap
    implicitHeight: Math.max(Theme.controlH, head.implicitHeight) + 2
    property string title: ""
    property string backName: ""
    signal back()

    activeFocusOnTab: true
    Keys.onReturnPressed: hd.back()
    Keys.onEnterPressed: hd.back()
    Keys.onSpacePressed: hd.back()
    Accessible.role: Accessible.Button
    Accessible.name: hd.backName !== "" ? hd.backName : hd.title

    Row {
        id: head
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.gap + 2
        // The back key: a round keycap (Block) that sinks while pressed.
        Block {
            id: key
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34 + Theme.shadowDy
            radius: Theme.rFull
            ringScale: 0.5
            fill: Theme.containerHigh
            pressed: area.pressed
            Icon {
                anchors.centerIn: parent
                name: "arrow_back"
                glyph: "←"
                size: 18
            }
        }
        Text {
            renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
            antialiasing: !Theme.pixelType
            font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Theme.shadowDy / 2
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.weight: Theme.wBold
            font.family: Theme.fam(text, Theme.families)
            text: hd.title
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: hd.back()
    }
    FocusRing {
        anchors.fill: parent
        shown: hd.activeFocus
        corner: Theme.rSm
    }
}
