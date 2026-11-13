import QtQuick
import "../core"
import "groups.js" as G

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
    // Groups (I502, W80; docs/ux/groups.md "Round two"): a zone's or a sidebar's list, whose `group:<id>` entries stand for
    // `layout.groups` records. A group row shows its members under it; a drop of one row onto another (or Ctrl+Down/Up)
    // groups them, joins or (after a confirm) merges; a member leaves by its button, Ctrl+Left or a drop on the list's end.
    // Each gesture is `regrouped({list, groups})`, one apply of both values; the rows follow the daemon's answer only.
    property bool groupable: false
    property var groups: []
    // A merge waiting for its confirm: {from, into} (group ids), or null.
    property var askMerge: null
    // The value a drag carries, "" while none.
    property string dragging: ""
    property bool dragActive: false
    signal regrouped(var res)

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
        // A group's member is listed (inside its group): not offered again.
        return choices.filter(function (c) { return items.indexOf(c.value) < 0 && l.groupOf(c.value) === "" })
    }
    // --- groups ---
    function groupOf(m) { return l.groupable ? G.groupOf(items, groups, m) : "" }
    function recordOf(id) { return G.recordOf(groups, id) }
    function membersOf(v) { return G.isGroup(v) ? G.membersOf(G.recordOf(groups, G.idOf(v))) : [] }
    function groupName(id) {
        var rec = G.recordOf(groups, id)
        return rec && rec.name ? rec.name : id
    }
    // One gesture's result to the daemon; the focus follows `focus` once the list it asked for is shown.
    function send(res, focus) {
        if (!res) return
        focusValue = focus
        focusAfter = JSON.stringify(res.list)
        regrouped(res)
    }
    // `a` dropped onto `b` (a row or a member): a group onto a group asks first.
    function dropOnto(a, b) {
        if (!l.enabled || a === b) return
        var gb = G.isGroup(b) ? G.idOf(b) : groupOf(b)
        if (G.isGroup(a) && gb !== "" && G.idOf(a) !== gb) { askMerge = { from: G.idOf(a), into: gb }; return }
        if (gb !== "" && gb === groupOf(a)) return
        send(G.dropOnto(items, groups, a, b), a)
    }
    function confirmMerge() {
        var m = askMerge
        askMerge = null
        if (m) send(G.merge(items, groups, m.from, m.into), G.entryOf(m.into))
    }
    function leaveGroup(m) { send(G.leave(items, groups, m), m) }
    function ungroup(id) {
        var ms = G.membersOf(G.recordOf(groups, id))
        send(G.ungroup(items, groups, id), ms.length ? ms[0] : null)
    }
    // A press on a row's name: the floating row starts where the row is (it moves once the drag passes its threshold).
    function startDrag(v, name, area, mouse) {
        var p = dragLayer.mapFromItem(area, mouse.x - 16, mouse.y - proxy.height / 2)
        proxy.x = p.x
        proxy.y = p.y
        proxy.text = name
        l.dragging = v
    }
    function endDrag() {
        if (proxy.Drag.active) proxy.Drag.drop()
        l.dragActive = false
        l.dragging = ""
    }
    function setGroupField(id, field, value) {
        // Only the records change: the zone's list is not written (a default list stays the default).
        var g = G.setField(groups, id, field, value)
        if (g) regrouped({ list: null, groups: g })
    }
    // The row of `v` takes the focus; null means the add control. A member's focus goes to its row inside its group.
    function focusRow(v) {
        if (v === null) {
            if (l.free) freeAdder.focusInput()
            else adder.forceActiveFocus()
            return
        }
        var i = items.indexOf(v)
        var row = i >= 0 ? rep.itemAt(i) : null
        if (!row && groupOf(v) !== "") {
            var gi = items.indexOf(G.entryOf(groupOf(v)))
            row = gi >= 0 ? rep.itemAt(gi) : null
            if (row && row.memberRow(v)) { row.memberRow(v).forceActiveFocus(); return }
        }
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
            readonly property bool isGroup: l.groupable && G.isGroup(entry.chosen)
            readonly property string gid: entry.isGroup ? G.idOf(entry.chosen) : ""
            readonly property var members: entry.isGroup ? l.membersOf(entry.chosen) : []
            readonly property string name: entry.isGroup ? l.groupName(entry.gid) : l.nameOf(entry.chosen)
            readonly property bool known: l.free || l.offer(entry.chosen) !== null || entry.isGroup && l.recordOf(entry.gid) !== null
            // The reason an entry cannot be drawn (`problems`, K72), as text: a second line under its name.
            readonly property string reason: entry.chosen !== undefined && l.reasons[entry.chosen] ? I18n.tr(l.reasons[entry.chosen]) : ""
            readonly property bool merging: entry.isGroup && l.askMerge !== null && l.askMerge.into === entry.gid
            function memberRow(m) {
                var i = entry.members.indexOf(m)
                return i >= 0 ? memberRep.itemAt(i) : null
            }
            width: l.width
            height: head.height + (entry.isGroup ? groupBody.height + Theme.gap / 2 : 0)
            radius: Theme.rSm
            color: entry.activeFocus || drop.containsDrag ? Theme.containerHigh : Theme.container
            border.width: drop.containsDrag ? 2 : 1
            border.color: drop.containsDrag ? Theme.accent : Theme.outline
            opacity: l.enabled ? 1 : 0.5
            activeFocusOnTab: l.enabled
            objectName: "pickrow:" + entry.chosen
            Keys.onPressed: event => {
                if (!l.enabled) return
                var ctrl = (event.modifiers & Qt.ControlModifier) && l.groupable
                if (ctrl && (event.key === Qt.Key_Down || event.key === Qt.Key_Up)) {
                    // Drop onto the next / previous row (W80): group with it, join it, or ask to merge.
                    var j = entry.index + (event.key === Qt.Key_Down ? 1 : -1)
                    if (j >= 0 && j < l.items.length) l.dropOnto(entry.chosen, l.items[j])
                    event.accepted = true
                } else if (l.askMerge !== null && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                    l.confirmMerge()
                    event.accepted = true
                } else if (l.askMerge !== null && event.key === Qt.Key_Escape) {
                    l.askMerge = null
                    event.accepted = true
                } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up) {
                    l.moveBy(entry.chosen, -1)
                    event.accepted = true
                } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Down) {
                    l.moveBy(entry.chosen, 1)
                    event.accepted = true
                } else if (entry.isGroup && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
                    l.ungroup(entry.gid)
                    event.accepted = true
                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    l.removeValue(entry.chosen)
                    event.accepted = true
                }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: (entry.index + 1) + ". " + (entry.isGroup
                ? I18n.fmt("settings.groups.a11y_group", { name: entry.name, n: entry.members.length })
                : entry.name) + (entry.reason !== "" ? ". " + entry.reason : "")

            // A drop on the row (W80): onto a module groups, onto a group joins (a group onto a group asks first).
            DropArea {
                id: drop
                anchors.fill: parent
                keys: ["kurashi-pick"]
                enabled: l.groupable && l.enabled && l.dragging !== "" && l.dragging !== entry.chosen
                    && entry.members.indexOf(l.dragging) < 0
                onDropped: l.dropOnto(l.dragging, entry.chosen)
            }
            Item {
                id: head
                width: parent.width
                height: Math.max(Theme.controlH, textCol.implicitHeight + 8)
                // The row's name is its drag handle (a press and a move; a click alone does nothing new).
                MouseArea {
                    id: dragArea
                    anchors.fill: textCol
                    enabled: l.groupable && l.enabled
                    preventStealing: true
                    cursorShape: enabled ? Qt.OpenHandCursor : Qt.ArrowCursor
                    drag.target: l.groupable ? proxy : null
                    drag.threshold: 6
                    readonly property bool dragOn: drag.active
                    onDragOnChanged: l.dragActive = dragOn
                    onPressed: mouse => l.startDrag(entry.chosen, entry.name, dragArea, mouse)
                    onReleased: l.endDrag()
                }
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
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
                        width: parent.width
                        // A path keeps its start and its last folder in view.
                        elide: l.paths ? Text.ElideMiddle : Text.ElideRight
                        color: entry.known ? Theme.fg : Theme.dim
                        font.pixelSize: Theme.fs
                        font.bold: entry.isGroup
                        font.family: Theme.fam(text, Theme.families)
                        text: (entry.index + 1) + ".  " + (entry.isGroup
                            ? I18n.fmt("settings.groups.row", { name: entry.name, n: entry.members.length }) : entry.name)
                    }
                    Text {
                        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
                        antialiasing: !Theme.pixelType
                        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
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
            }
            // A group's own controls and its members (W80): name, Accordion, Ungroup; each member with Leave group.
            Column {
                id: groupBody
                visible: entry.isGroup
                anchors.top: head.bottom
                anchors.left: parent.left
                anchors.leftMargin: Theme.pad * 2
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap / 2
                spacing: Theme.gap / 2
                height: entry.isGroup ? implicitHeight : 0
                Row {
                    visible: entry.merging
                    spacing: Theme.gap
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.fg
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        text: entry.merging ? I18n.fmt("settings.groups.merge_ask",
                            { from: l.groupName(l.askMerge.from), into: entry.name }) : ""
                    }
                    Button {
                        objectName: "groupmerge:" + entry.gid
                        label: I18n.tr("settings.groups.merge")
                        primary: true
                        onClicked: l.confirmMerge()
                    }
                    Button {
                        objectName: "groupmergecancel:" + entry.gid
                        label: I18n.tr("settings.groups.cancel")
                        onClicked: l.askMerge = null
                    }
                }
                Row {
                    spacing: Theme.gap
                    TextField {
                        objectName: "groupname:" + entry.gid
                        // What the switch, its word and Ungroup leave of the row.
                        width: Math.max(80, Math.min(220, groupBody.width - accSwitch.width - accWord.width - ungroupBtn.width - Theme.gap * 3))
                        label: I18n.fmt("settings.groups.name_of", { name: entry.name })
                        placeholder: entry.gid
                        value: { var r = l.recordOf(entry.gid); return r && r.name ? r.name : "" }
                        enabled: l.enabled
                        onAccepted: t => l.setGroupField(entry.gid, "name", t.trim())
                    }
                    Toggle {
                        id: accSwitch
                        objectName: "groupaccordion:" + entry.gid
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.fmt("settings.groups.accordion_of", { name: entry.name })
                        checked: { var r = l.recordOf(entry.gid); return !!(r && r.accordion) }
                        enabled: l.enabled
                        onToggled: v => l.setGroupField(entry.gid, "accordion", v)
                    }
                    Text {
                        id: accWord
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 1
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("settings.groups.accordion")
                    }
                    Button {
                        id: ungroupBtn
                        objectName: "groupungroup:" + entry.gid
                        anchors.verticalCenter: parent.verticalCenter
                        label: I18n.tr("settings.groups.ungroup")
                        accessibleName: I18n.fmt("settings.groups.ungroup_of", { name: entry.name })
                        enabled: l.enabled
                        onClicked: l.ungroup(entry.gid)
                    }
                }
                Repeater {
                    id: memberRep
                    model: entry.members.length
                    delegate: Rectangle {
                        id: mem
                        required property int index
                        readonly property string value: mem.index < entry.members.length ? entry.members[mem.index] : ""
                        readonly property string name: l.nameOf(mem.value)
                        width: groupBody.width
                        height: Theme.controlH
                        radius: Theme.rSm
                        color: mem.activeFocus || mdrop.containsDrag ? Theme.containerHigh : "transparent"
                        border.width: mdrop.containsDrag ? 2 : 1
                        border.color: mdrop.containsDrag ? Theme.accent : Theme.outline
                        activeFocusOnTab: l.enabled
                        objectName: "groupmember:" + mem.value
                        Accessible.role: Accessible.ListItem
                        Accessible.name: I18n.fmt("settings.groups.a11y_member", { item: mem.name, name: entry.name })
                        Keys.onPressed: event => {
                            if (!l.enabled) return
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Left) {
                                l.leaveGroup(mem.value)
                                event.accepted = true
                            }
                        }
                        DropArea {
                            id: mdrop
                            anchors.fill: parent
                            keys: ["kurashi-pick"]
                            enabled: l.enabled && l.dragging !== "" && l.dragging !== mem.value
                                && entry.members.indexOf(l.dragging) < 0 && l.dragging !== entry.chosen
                            onDropped: l.dropOnto(l.dragging, mem.value)
                        }
                        MouseArea {
                            id: mdrag
                            anchors.left: parent.left
                            anchors.right: leaveBtn.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            enabled: l.enabled
                            preventStealing: true
                            cursorShape: enabled ? Qt.OpenHandCursor : Qt.ArrowCursor
                            drag.target: proxy
                            drag.threshold: 6
                            readonly property bool dragOn: drag.active
                            onDragOnChanged: l.dragActive = dragOn
                            onPressed: mouse => l.startDrag(mem.value, mem.name, mdrag, mouse)
                            onReleased: l.endDrag()
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.pad
                            anchors.right: leaveBtn.left
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            color: l.offer(mem.value) !== null ? Theme.fg : Theme.dim
                            font.pixelSize: Theme.fs
                            font.family: Theme.fam(text, Theme.families)
                            text: "· " + mem.name
                        }
                        Button {
                            id: leaveBtn
                            objectName: "groupleave:" + mem.value
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            label: I18n.tr("settings.groups.leave")
                            accessibleName: I18n.fmt("settings.groups.leave_of", { item: mem.name, name: entry.name })
                            enabled: l.enabled
                            onClicked: l.leaveGroup(mem.value)
                        }
                        FocusRing {
                            anchors.fill: parent
                            shown: mem.activeFocus
                            corner: mem.radius
                        }
                    }
                }
            }
            FocusRing {
                anchors.fill: parent
                shown: entry.activeFocus
                corner: entry.radius
            }
        }
    }

    // A member dropped here leaves its group (W80): shown only while a member is being dragged.
    Rectangle {
        id: leaveZone
        readonly property bool shownNow: l.groupable && l.dragging !== "" && l.groupOf(l.dragging) !== ""
        visible: shownNow
        width: l.width
        height: shownNow ? Theme.controlH : 0
        radius: Theme.rSm
        color: leaveDrop.containsDrag ? Theme.containerHigh : "transparent"
        border.width: leaveDrop.containsDrag ? 2 : 1
        border.color: leaveDrop.containsDrag ? Theme.accent : Theme.outline
        objectName: "groupleavezone"
        Text {
            anchors.centerIn: parent
            color: Theme.dim
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            text: I18n.tr("settings.groups.drop_leave")
        }
        DropArea {
            id: leaveDrop
            anchors.fill: parent
            keys: ["kurashi-pick"]
            onDropped: l.leaveGroup(l.dragging)
        }
    }
    // The drag's floating row (W80): follows the pointer; a release drops it on the row under it.
    Item {
        id: dragLayer
        width: l.width
        height: 0
        z: 10
        Rectangle {
            id: proxy
            property string text: ""
            visible: l.dragging !== "" && l.dragActive
            Drag.active: l.dragActive
            width: Math.min(l.width, 260)
            height: Theme.controlH
            radius: Theme.rSm
            color: Theme.containerHigh
            border.width: 1
            border.color: Theme.accent
            opacity: 0.92
            Drag.keys: ["kurashi-pick"]
            Drag.hotSpot.x: 16
            Drag.hotSpot.y: height / 2
            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.pad
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: proxy.text
            }
        }
    }

    // A free list with no entries says so (and, for paths, what one looks like).
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        antialiasing: !Theme.pixelType
        font.hintingPreference: Theme.pixelType ? Font.PreferFullHinting : Font.PreferDefaultHinting
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
