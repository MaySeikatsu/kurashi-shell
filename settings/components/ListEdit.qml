import QtQuick
import "../core"

// String list: removable items plus an add field. Emits the full new list. Each item takes Tab focus;
// Delete, Backspace, Return or Space removes it, and the × does the same with a pointer.
Flow {
    id: l
    property var items: []
    property bool enabled: true
    property string label: ""
    signal edited(var items)

    spacing: Theme.gap / 2

    function remove(i) {
        var next = l.items.slice()
        next.splice(i, 1)
        l.edited(next)
    }

    Repeater {
        model: l.items
        delegate: Rectangle {
            id: entry
            required property var modelData
            required property int index
            implicitWidth: lbl.implicitWidth + cross.implicitWidth + 2 * Theme.gap
            implicitHeight: 26
            radius: Theme.rFull
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            opacity: l.enabled ? 1 : 0.5
            activeFocusOnTab: l.enabled
            // Matched by key code: Qt has no Keys signal for Backspace.
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Delete: case Qt.Key_Backspace: case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space:
                    l.remove(entry.index)
                    event.accepted = true
                    break
                }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: I18n.fmt("settings.ui.list_remove", { item: modelData })

            Text {
                id: lbl
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: entry.modelData
            }
            Text {
                id: cross
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.dim
                font.pixelSize: Theme.fs
                text: "×"
                MouseArea {
                    // A 32 px hit area around the glyph; the chip itself keeps its 26 px.
                    anchors.centerIn: parent
                    width: Math.max(Theme.controlH, cross.implicitWidth)
                    height: Theme.controlH
                    enabled: l.enabled
                    onClicked: l.remove(entry.index)
                }
            }
            FocusRing {
                anchors.fill: parent
                shown: entry.activeFocus
                corner: entry.radius
            }
        }
    }
    TextField {
        width: 120
        height: Theme.controlH
        label: l.label !== "" ? l.label : I18n.tr("settings.ui.list_add")
        enabled: l.enabled
        placeholder: I18n.tr("settings.ui.list_add")
        onAccepted: text => {
            var v = text.trim()
            if (v !== "" && l.items.indexOf(v) < 0) l.edited(l.items.concat([v]))
        }
    }
}
