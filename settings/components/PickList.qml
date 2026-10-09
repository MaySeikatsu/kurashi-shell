import QtQuick
import "../core"

// Ordered pick list (I9; UX brief, settings: "vertical pick list"): one row per chosen offer, in order, with move up,
// move down and remove. Alt+Up and Alt+Down move the focused row (it keeps the focus), Delete or Backspace removes it.
// The add control under the rows lists the offers not chosen yet. Every change emits the full new list, which the
// daemon keeps or refuses as one value. The list has one provenance: its row's chip.
Column {
    id: l
    // Offers {value, label (i18n key), enabled?, reason? (i18n key)}; items: the chosen values, in order.
    property var choices: []
    property var items: []
    property bool enabled: true
    // The row's label: the add control's accessible name.
    property string label: ""
    signal edited(var items)

    spacing: Theme.gap / 2
    // The row to focus once the daemon answers with the moved list (the rows are rebuilt by then).
    property int focusIndex: -1

    // The offer a chosen value stands for, or null: a value no offer names is shown as it is (not available now).
    function offer(v) {
        for (var i = 0; i < choices.length; i++) if (choices[i].value === v) return choices[i]
        return null
    }
    function nameOf(v) {
        var o = offer(v)
        return o ? I18n.tr(o.label) : String(v)
    }
    function remaining() {
        return choices.filter(function (c) { return items.indexOf(c.value) < 0 })
    }
    function moveBy(i, d) {
        var j = i + d
        if (j < 0 || j >= items.length) return
        var next = items.slice()
        next[i] = items[j]
        next[j] = items[i]
        focusIndex = j
        edited(next)
    }
    function removeAt(i) {
        var next = items.slice()
        next.splice(i, 1)
        focusIndex = Math.min(i, next.length - 1)
        edited(next)
    }
    // Not `add`: a Column is a Positioner, which already has an `add` transition.
    function addOffer(v) {
        if (items.indexOf(v) < 0) {
            focusIndex = -1
            edited(items.concat([v]))
        }
    }

    Repeater {
        id: rows
        model: l.items
        delegate: Rectangle {
            id: entry
            required property var modelData
            required property int index
            readonly property string name: l.nameOf(modelData)
            readonly property bool known: l.offer(modelData) !== null
            width: l.width
            height: Theme.controlH
            radius: Theme.rSm
            color: entry.activeFocus ? Theme.containerHigh : Theme.container
            border.width: 1
            border.color: Theme.outline
            opacity: l.enabled ? 1 : 0.5
            activeFocusOnTab: l.enabled
            Keys.onPressed: event => {
                if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up) {
                    l.moveBy(entry.index, -1)
                    event.accepted = true
                } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Down) {
                    l.moveBy(entry.index, 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    l.removeAt(entry.index)
                    event.accepted = true
                }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: (entry.index + 1) + ". " + entry.name
            // A row rebuilt by a move takes the focus its row had: the moved one, at its new place (the rows are new
            // objects after each change, so this runs as each is created).
            Component.onCompleted: if (entry.index === l.focusIndex) { l.focusIndex = -1; entry.forceActiveFocus() }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.pad
                anchors.right: buttons.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                color: entry.known ? Theme.fg : Theme.dim
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: (entry.index + 1) + ".  " + entry.name
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Button {
                    label: "↑"
                    accessibleName: I18n.fmt("settings.ui.pick_up", { item: entry.name })
                    enabled: l.enabled && entry.index > 0
                    onClicked: l.moveBy(entry.index, -1)
                }
                Button {
                    label: "↓"
                    accessibleName: I18n.fmt("settings.ui.pick_down", { item: entry.name })
                    enabled: l.enabled && entry.index < l.items.length - 1
                    onClicked: l.moveBy(entry.index, 1)
                }
                Button {
                    label: "×"
                    accessibleName: I18n.fmt("settings.ui.list_remove", { item: entry.name })
                    enabled: l.enabled
                    onClicked: l.removeAt(entry.index)
                }
            }
            FocusRing {
                anchors.fill: parent
                shown: entry.activeFocus
                corner: entry.radius
            }
        }
    }

    Select {
        id: adder
        width: Math.min(l.width, 360)
        choices: l.remaining()
        current: undefined
        placeholder: l.remaining().length ? I18n.tr("settings.ui.pick_add") : I18n.tr("settings.ui.pick_none_left")
        label: I18n.tr("settings.ui.pick_add")
        enabled: l.enabled && l.remaining().length > 0
        onPicked: v => l.addOffer(v)
    }
}
