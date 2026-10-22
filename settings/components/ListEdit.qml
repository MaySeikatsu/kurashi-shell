import QtQuick
import "../core"

// String list as removable chips plus an add field (the launcher's terminal command, the font chain). Each chip takes
// Tab focus; Delete or Backspace removes it, and its × does the same with a pointer. Return in the add field adds the
// typed text; Return in an empty field is `keepRequested` (a previewed list is kept there). Escape is `cancelled`.
Flow {
    id: l
    property var items: []
    property bool enabled: true
    property string label: ""
    signal edited(var items)
    signal keepRequested()
    signal cancelled()
    // Escape is taken only while there is something to take back (the row binds its open preview); otherwise it goes on
    // up, where the sheet closes on it (K63).
    property bool cancellable: true

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
            implicitWidth: lbl.implicitWidth + cross.implicitWidth + 2 * Theme.gap + 4
            implicitHeight: Theme.controlH - 6
            radius: Theme.rFull
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.outline
            opacity: l.enabled ? 1 : 0.5
            activeFocusOnTab: l.enabled
            // Matched by key code: Qt has no Keys signal for Backspace.
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Delete: case Qt.Key_Backspace:
                    l.remove(entry.index)
                    event.accepted = true
                    break
                case Qt.Key_Escape:
                    if (l.cancellable) l.cancelled()
                    event.accepted = l.cancellable
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
                    // A 32 px hit area around the glyph; the chip itself keeps its height.
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
        id: add
        width: 140
        height: Theme.controlH
        label: l.label !== "" ? l.label : I18n.tr("settings.ui.list_add")
        enabled: l.enabled
        placeholder: I18n.tr("settings.ui.list_add")
        onSubmitted: text => {
            var v = text.trim()
            if (v === "") { l.keepRequested(); return }
            if (l.items.indexOf(v) < 0) l.edited(l.items.concat([v]))
            add.clear()
        }
        escapeTaken: l.cancellable
        onEscaped: if (l.cancellable) l.cancelled()
    }
}
