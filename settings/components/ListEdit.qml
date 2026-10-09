import QtQuick
import "../core"

// String list: removable items plus an add field. Emits the full new list.
Flow {
    id: l
    property var items: []
    property bool enabled: true
    signal edited(var items)

    spacing: Theme.gap / 2
    Repeater {
        model: l.items
        delegate: Rectangle {
            required property var modelData
            required property int index
            implicitWidth: lbl.implicitWidth + x.implicitWidth + 2 * Theme.gap
            implicitHeight: 26
            radius: Theme.rFull
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            opacity: l.enabled ? 1 : 0.5
            Text {
                id: lbl
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: modelData
            }
            Text {
                id: x
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.dim
                font.pixelSize: Theme.fs
                text: "×"
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    enabled: l.enabled
                    onClicked: {
                        var next = l.items.slice()
                        next.splice(index, 1)
                        l.edited(next)
                    }
                }
            }
        }
    }
    TextField {
        width: 120
        height: 26
        enabled: l.enabled
        placeholder: I18n.tr("settings.ui.list_add")
        onAccepted: text => {
            var v = text.trim()
            if (v !== "" && l.items.indexOf(v) < 0) l.edited(l.items.concat([v]))
        }
    }
}
