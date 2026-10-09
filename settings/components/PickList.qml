import QtQuick
import "../core"

// Ordered pick list (I9; UX brief, settings "Design": vertical pick list): one row per chosen offer, in order, with move up,
// move down and remove. Alt+Up and Alt+Down move the focused row and Delete or Backspace removes it. A move keeps the focus
// on the moved row; a removed row hands it to the next one. The add control under the rows lists the offers not chosen yet.
// Every change emits the full new list, which the daemon keeps or refuses as one value; the rows show the daemon's list
// only (Shōjiki: nothing is shown before it is in effect). The list has one provenance: its row's chip.
Column {
    id: l
    // Offers {value, label (i18n key), enabled?, reason? (i18n key)}; items: the chosen values, in order.
    property var choices: []
    property var items: []
    property bool enabled: true
    // The row's label: the add control's accessible name.
    property string label: ""
    // The daemon refused the last change (the row's refusal line says why): the focus stays where it was.
    property bool refused: false
    signal edited(var items)

    spacing: Theme.gap / 2
    // The value whose row takes the focus once the daemon's list is shown: a value, null (the add control) or undefined (no
    // focus change). Set by a move or a removal, used by onItemsChanged.
    property var focusValue: undefined

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
    // The row of `v` takes the focus; null means the add control.
    function focusRow(v) {
        if (v === null) { adder.forceActiveFocus(); return }
        var i = items.indexOf(v)
        var row = i >= 0 ? rep.itemAt(i) : null
        if (row) row.forceActiveFocus()
    }
    // Every change goes to the daemon as the whole list; the rows follow its answer.
    function moveBy(v, d) {
        var i = items.indexOf(v)
        var j = i + d
        if (i < 0 || j < 0 || j >= items.length) return
        var next = items.slice()
        next[i] = items[j]
        next[j] = items[i]
        focusValue = v
        edited(next)
    }
    function removeValue(v) {
        var i = items.indexOf(v)
        if (i < 0) return
        var next = items.slice()
        next.splice(i, 1)
        focusValue = i + 1 < items.length ? items[i + 1] : (i > 0 ? items[i - 1] : null)
        edited(next)
    }
    // Not `add`: a Column is a Positioner, which already has an `add` transition.
    function addOffer(v) {
        if (items.indexOf(v) < 0) {
            focusValue = undefined
            edited(items.concat([v]))
        }
    }

    onItemsChanged: {
        if (focusValue !== undefined) {
            var f = focusValue
            focusValue = undefined
            // After the rows show the daemon's list (a removed row's slot is gone only once the count has changed).
            Qt.callLater(function () { l.focusRow(f) })
        }
    }
    onRefusedChanged: if (refused) focusValue = undefined

    // One row per slot: slot i shows the i-th chosen value. A move changes the values the slots show, not the slots, so no
    // row is rebuilt and the focus stays on its slot until focusRow moves it to the slot the moved value has now. (Rows keyed
    // by their value were rebuilt after each move, and a rebuilt row lost the focus, so the next Alt+Up never reached it.)
    Repeater {
        id: rep
        model: l.items.length
        delegate: Rectangle {
            id: entry
            required property int index
            readonly property var chosen: entry.index < l.items.length ? l.items[entry.index] : undefined
            readonly property string name: l.nameOf(entry.chosen)
            readonly property bool known: l.offer(entry.chosen) !== null
            width: l.width
            height: Theme.controlH
            radius: Theme.rSm
            color: entry.activeFocus ? Theme.containerHigh : Theme.container
            border.width: 1
            border.color: Theme.outline
            opacity: l.enabled ? 1 : 0.5
            activeFocusOnTab: l.enabled
            objectName: "pickrow:" + entry.chosen
            Keys.onPressed: event => {
                if (!l.enabled) return
                if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up) {
                    l.moveBy(entry.chosen, -1)
                    event.accepted = true
                } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Down) {
                    l.moveBy(entry.chosen, 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    l.removeValue(entry.chosen)
                    event.accepted = true
                }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: (entry.index + 1) + ". " + entry.name

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
                    objectName: "pickup:" + entry.chosen
                    label: "↑"
                    accessibleName: I18n.fmt("settings.ui.pick_up", { item: entry.name })
                    enabled: l.enabled && entry.index > 0
                    onClicked: l.moveBy(entry.chosen, -1)
                }
                Button {
                    objectName: "pickdown:" + entry.chosen
                    label: "↓"
                    accessibleName: I18n.fmt("settings.ui.pick_down", { item: entry.name })
                    enabled: l.enabled && entry.index < l.items.length - 1
                    onClicked: l.moveBy(entry.chosen, 1)
                }
                Button {
                    objectName: "pickremove:" + entry.chosen
                    label: "×"
                    accessibleName: I18n.fmt("settings.ui.list_remove", { item: entry.name })
                    enabled: l.enabled
                    onClicked: l.removeValue(entry.chosen)
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
