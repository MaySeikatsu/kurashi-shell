import QtQuick
import "../core"

// Ordered pick list (I9; UX brief, settings "Design": vertical pick list): one row per chosen offer, in order, with move up,
// move down and remove. Alt+Up and Alt+Down move the focused row and Delete or Backspace removes it. A move keeps the focus
// on the moved row; a removed row hands it to the next one. The add control under the rows lists the offers not chosen yet.
// Every change emits the full new list, which the daemon keeps or refuses as one value; the rows show the daemon's list
// only (Shōjiki: nothing is shown before it is in effect). The list has one provenance: its row's chip.
// `free` (I54): a free string list — a mod's `list` without choices, the launcher's command, the dock's pins. The same rows,
// in order, and a text field to add one: Return adds the typed entry (an entry already listed is not added twice). The
// field keeps a refused entry with its edge marked, so it can be corrected (the row says why under the control); it clears
// once the daemon lists the entry. `paths` (a list whose `unit` is `path`): the field and the empty line say what a path
// looks like, and the daemon refuses an entry that is not an absolute or `~` path.
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
    // A free list (no offers: a text field adds entries), and one of paths (the field hints at the form).
    property bool free: false
    property bool paths: false
    // The entries the layout cannot draw (`problems`, K72): {value: reason i18n key}. Such an entry says why under its name;
    // its remove button stays.
    property var reasons: ({})
    // The entry typed into the free list's field and sent; the field clears once the daemon lists it.
    property string pending: ""
    signal edited(var items)

    spacing: Theme.gap / 2
    // The value whose row takes the focus once the daemon's list is shown: a value, null (the add control) or undefined (no
    // focus change). Set by a move or a removal, used by onItemsChanged.
    property var focusValue: undefined
    // The list that change asked for (JSON): the focus waits for it, not for any other refresh of the same list that may come
    // first (the row re-reads its value on every config change).
    property string focusAfter: ""

    // The offer a chosen value stands for, or null: a value no offer names is shown as it is (not available now).
    function offer(v) {
        for (var i = 0; i < choices.length; i++) if (choices[i].value === v) return choices[i]
        return null
    }
    function nameOf(v) {
        var o = l.free ? null : offer(v)
        return o ? I18n.tr(o.label) : String(v)
    }
    function remaining() {
        return choices.filter(function (c) { return items.indexOf(c.value) < 0 })
    }
    // The row of `v` takes the focus; null means the add control.
    function focusRow(v) {
        if (v === null) {
            if (l.free) freeAdder.focusInput()
            else adder.forceActiveFocus()
            return
        }
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
        focusAfter = JSON.stringify(next)
        edited(next)
    }
    function removeValue(v) {
        var i = items.indexOf(v)
        if (i < 0) return
        var next = items.slice()
        next.splice(i, 1)
        focusValue = i + 1 < items.length ? items[i + 1] : (i > 0 ? items[i - 1] : null)
        focusAfter = JSON.stringify(next)
        edited(next)
    }
    // Not `add`: a Column is a Positioner, which already has an `add` transition.
    function addOffer(v) {
        if (items.indexOf(v) < 0) {
            focusValue = undefined
            edited(items.concat([v]))
        }
    }
    // A free list's typed entry: trimmed; blank adds nothing, one already listed only clears the field.
    function addTyped(t) {
        var v = String(t).trim()
        if (v === "") return
        if (items.indexOf(v) >= 0) { freeAdder.clear(); pending = ""; return }
        pending = v
        addOffer(v)
    }

    onItemsChanged: {
        if (pending !== "" && items.indexOf(pending) >= 0) {
            pending = ""
            freeAdder.clear()
        }
        if (focusValue !== undefined && (focusAfter === "" || JSON.stringify(items) === focusAfter)) {
            var f = focusValue
            focusValue = undefined
            focusAfter = ""
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
            readonly property bool known: l.free || l.offer(entry.chosen) !== null
            // The reason an entry cannot be drawn (`problems`, K72), as text: a second line under its name.
            readonly property string reason: entry.chosen !== undefined && l.reasons[entry.chosen] ? I18n.tr(l.reasons[entry.chosen]) : ""
            width: l.width
            height: Math.max(Theme.controlH, textCol.implicitHeight + 8)
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
            Accessible.name: (entry.index + 1) + ". " + entry.name + (entry.reason !== "" ? ". " + entry.reason : "")

            Column {
                id: textCol
                anchors.left: parent.left
                anchors.leftMargin: Theme.pad
                anchors.right: buttons.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    width: parent.width
                    // A path keeps its start and its last folder in view.
                    elide: l.paths ? Text.ElideMiddle : Text.ElideRight
                    color: entry.known ? Theme.fg : Theme.dim
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: (entry.index + 1) + ".  " + entry.name
                }
                Text {
                    renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                    visible: entry.reason !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: entry.reason
                }
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

    // A free list with no entries says so (and, for paths, what one looks like).
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        visible: l.free && l.items.length === 0
        width: l.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr(l.paths ? "settings.ui.list_empty_paths" : "settings.ui.list_empty")
    }
    TextField {
        id: freeAdder
        visible: l.free
        objectName: "listadd"
        width: Math.min(l.width, 360)
        label: l.label !== "" ? I18n.fmt("settings.ui.list_add_to", { list: l.label }) : I18n.tr("settings.ui.list_add")
        placeholder: I18n.tr(l.paths ? "settings.ui.list_add_path" : "settings.ui.list_add")
        mono: l.paths
        enabled: l.enabled
        invalid: l.refused && l.pending !== ""
        onSubmitted: t => l.addTyped(t)
    }
    Select {
        id: adder
        visible: !l.free
        width: Math.min(l.width, 360)
        choices: l.remaining()
        current: undefined
        placeholder: l.remaining().length ? I18n.tr("settings.ui.pick_add") : I18n.tr("settings.ui.pick_none_left")
        label: I18n.tr("settings.ui.pick_add")
        enabled: l.enabled && l.remaining().length > 0
        onPicked: v => l.addOffer(v)
    }
}
