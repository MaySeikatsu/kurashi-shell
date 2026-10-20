import QtQuick
import qs.core
import qs.components

// A centred message in a card's body (the cold engine, an empty dock, a view that is not there), with an optional button.
Item {
    id: notice
    property string text: ""
    property string actionLabel: ""
    signal actionPressed()

    Column {
        anchors.centerIn: parent
        width: notice.width - 2 * Theme.pad
        spacing: Theme.gap
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: notice.text
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
        }
        Item {
            visible: notice.actionLabel !== ""
            width: parent.width
            height: visible ? action.height : 0
            Button {
                id: action
                anchors.horizontalCenter: parent.horizontalCenter
                label: notice.actionLabel
                primary: true
                onClicked: notice.actionPressed()
            }
        }
    }
}
