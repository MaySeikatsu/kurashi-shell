import QtQuick
import "../../core"
import ".."

// The top row of a drill-down page (W13): "← Title". The whole header is the Back control: Enter, Space or a click go back
// (Esc and Left are handled by the card, QuickPanel). It is the first Tab stop of every page.
Item {
    id: hd
    implicitWidth: head.implicitWidth + 2 * Theme.gap
    implicitHeight: Math.max(Theme.controlH, head.implicitHeight)
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
        anchors.leftMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.gap
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.dim
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            text: "←"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            font.pixelSize: Theme.fsTitle
            font.family: Theme.fam(text, Theme.families)
            text: hd.title
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: hd.back()
    }
    FocusRing {
        anchors.fill: parent
        shown: hd.activeFocus
        corner: Theme.rSm
    }
}
