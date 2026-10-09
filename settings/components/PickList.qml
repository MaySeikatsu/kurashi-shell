import QtQuick
import "../core"

// Ordered pick list (I9, a `pick_list` row): the chosen offers in order, each with move up, move down and
// remove; the add control lists the offers not chosen yet. Every change emits the full new list, which the
// daemon keeps or refuses as one value. Glyph buttons keep the 32 px floor and name their item for screen readers.
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
        edited(next)
    }
    function removeAt(i) {
        var next = items.slice()
        next.splice(i, 1)
        edited(next)
    }
    // Not `add`: a Column is a Positioner, which already has an `add` transition.
    function addOffer(v) {
        if (items.indexOf(v) < 0) edited(items.concat([v]))
    }

    Flow {
        width: parent.width
        spacing: Theme.gap / 2

        Repeater {
            model: l.items
            delegate: Rectangle {
                id: entry
                required property var modelData
                required property int index
                readonly property string name: l.nameOf(modelData)
                readonly property bool known: l.offer(modelData) !== null
                height: Theme.controlH
                width: row.width + 2 * Theme.gap
                radius: Theme.rSm
                // One step darker than the glyph buttons on it, so each button shows its own area.
                color: Theme.container
                border.width: 1
                border.color: Theme.outline
                opacity: l.enabled ? 1 : 0.5

                Row {
                    id: row
                    x: Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: entry.known ? Theme.fg : Theme.dim
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: (entry.index + 1) + ". " + entry.name
                    }
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
            }
        }

        Select {
            id: adder
            width: 220
            choices: l.remaining()
            current: undefined
            placeholder: l.remaining().length ? I18n.tr("settings.ui.pick_add") : I18n.tr("settings.ui.pick_none_left")
            label: I18n.tr("settings.ui.pick_add")
            enabled: l.enabled && l.remaining().length > 0
            onPicked: v => l.addOffer(v)
        }
    }
}
