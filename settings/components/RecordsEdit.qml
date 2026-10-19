import QtQuick
import "../core"

// The records editor (K38, MODS.md "Records"; UX brief docs/ux/settings.md "Records" and docs/ux/webdock.md "Pins"): one row
// per record, named by its item_label, with move up, move down, edit and remove, and a form for the add and the edit with one
// control per declared field. A refusal shows at the field it names (the daemon's rejected path, row and field). Every change
// emits the whole list, which the daemon keeps or refuses as one value; the rows show the daemon's list only (Shōjiki). Enter
// in a field saves the form, Escape cancels it; Up and Down move between the rows, Alt+Up and Alt+Down move the focused row,
// Delete removes it, Enter opens its form.
Column {
    id: rec
    // The declared record as the schema lists it: fields {key, type, required, default?, label, choices?, schemes?, range?},
    // unique?, item_label?.
    property var spec: ({})
    // The daemon's rows, every declared field present, in order.
    property var items: []
    property bool enabled: true
    property string label: ""
    // The daemon's refusal of the last change: {index, field, text}; null when none names a field.
    property var refusal: null
    signal edited(var items)

    readonly property var fields: rec.spec.fields ?? []
    readonly property string nameKey: rec.spec.item_label ?? (rec.fields.length ? rec.fields[0].key : "")

    // The form: -1 closed, rec.items.length for an add, else the index of the row being edited.
    property int formRow: -1
    property var draft: ({})
    // A change the form sent: the form closes when the daemon's list arrives and stays open when it refuses.
    property bool pending: false
    // The row that takes the focus after a move or a removal (-1: none).
    property int focusIndex: -1

    spacing: Theme.gap / 2

    function nameOf(row) {
        var v = row ? row[rec.nameKey] : undefined
        return v === undefined || v === null || String(v) === "" ? I18n.tr("settings.records.untitled") : String(v)
    }
    // The first address of a row, under its name (a url field other than the name).
    function detailOf(row) {
        for (var i = 0; i < rec.fields.length; i++) {
            var f = rec.fields[i]
            if (f.type === "url" && f.key !== rec.nameKey && row && row[f.key] !== undefined) return String(row[f.key])
        }
        return ""
    }
    function blankDraft() {
        var d = {}
        rec.fields.forEach(function (f) { if (f.default !== undefined) d[f.key] = f.default })
        return d
    }
    function draftText(key) {
        var v = rec.draft[key]
        return v === undefined || v === null ? "" : String(v)
    }
    // What a typed text is as a value of its field: an empty text is no value, a number is a number.
    function typed(kind, t) {
        if (kind === "int") {
            if (t.trim() === "") return undefined
            var n = Number(t)
            return isNaN(n) ? t : n
        }
        return t === "" ? undefined : t
    }
    function setDraft(key, v) {
        var d = Object.assign({}, rec.draft)
        if (v === undefined) delete d[key]
        else d[key] = v
        rec.draft = d
    }
    function fieldError(key) {
        return rec.formRow >= 0 && rec.refusal && rec.refusal.index === rec.formRow && rec.refusal.field === key
            ? rec.refusal.text : ""
    }
    function openAdd() {
        if (!rec.enabled) return
        rec.draft = rec.blankDraft()
        rec.formRow = rec.items.length
        rec.pending = false
        Qt.callLater(function () { rec.focusFieldAt(0) })
    }
    function openEdit(i) {
        if (!rec.enabled || i < 0 || i >= rec.items.length) return
        rec.draft = Object.assign({}, rec.items[i])
        rec.formRow = i
        rec.pending = false
        Qt.callLater(function () { rec.focusFieldAt(0) })
    }
    function closeForm() {
        rec.formRow = -1
        rec.draft = ({})
        rec.pending = false
    }
    // Escape and Cancel: the form closes and the focus goes back to the row it opened from (the add button for an add).
    // The field that had the focus leaves the window with the form, and then the focus is nowhere (I81).
    function cancelForm() {
        var at = rec.formRow
        rec.closeForm()
        Qt.callLater(function () { rec.focusRow(at) })
    }
    // Every change goes to the daemon as the whole list; the rows follow its answer.
    function submit() {
        if (!rec.enabled || rec.formRow < 0) return
        var next = rec.items.slice()
        var row = Object.assign({}, rec.draft)
        if (rec.formRow >= rec.items.length) next.push(row)
        else next[rec.formRow] = row
        rec.pending = true
        rec.edited(next)
    }
    function removeAt(i) {
        if (!rec.enabled || i < 0 || i >= rec.items.length) return
        var next = rec.items.slice()
        next.splice(i, 1)
        // The row that takes its place; -2 when none is left, so the focus goes to the add control.
        rec.focusIndex = next.length > 0 ? Math.min(i, next.length - 1) : -2
        rec.edited(next)
    }
    function moveBy(i, d) {
        var j = i + d
        if (!rec.enabled || i < 0 || j < 0 || j >= rec.items.length) return
        var next = rec.items.slice()
        var t = next[i]
        next[i] = next[j]
        next[j] = t
        rec.focusIndex = j
        rec.edited(next)
    }
    function focusRow(i) {
        var r = rowRep.itemAt(i)
        if (r) r.forceActiveFocus()
        else addButton.forceActiveFocus()
    }
    function focusFieldAt(i) {
        var d = formRep.itemAt(i)
        if (d) d.focusControl()
    }

    // The daemon re-publishes the schema often; only a list that differs from the last one is an answer to the form.
    property string seen: ""
    onItemsChanged: {
        const sig = JSON.stringify(rec.items)
        if (sig === rec.seen) return
        rec.seen = sig
        // A saved form closes, and the focus goes to the entry it saved (a new entry is the last one).
        if (rec.pending) { rec.focusIndex = rec.formRow; rec.closeForm() }
        if (rec.focusIndex >= 0) {
            var f = rec.focusIndex
            rec.focusIndex = -1
            // After the rows show the daemon's list (a removed row's slot is gone only once the count has changed).
            Qt.callLater(function () { rec.focusRow(f) })
        } else if (rec.focusIndex === -2) {
            rec.focusIndex = -1
            Qt.callLater(function () { addButton.forceActiveFocus() })
        }
    }

    // One row per record, in order. Up and Down move the focus between rows; Alt+Up and Alt+Down move the row.
    Repeater {
        id: rowRep
        model: rec.items.length
        delegate: Rectangle {
            id: entry
            required property int index
            readonly property var row: entry.index < rec.items.length ? rec.items[entry.index] : ({})
            readonly property string name: rec.nameOf(entry.row)
            width: rec.width
            height: Math.max(Theme.controlH, labelCol.implicitHeight + Theme.gap)
            radius: Theme.rSm
            color: entry.activeFocus ? Theme.containerHigh : Theme.container
            border.width: 1
            border.color: Theme.outline
            opacity: rec.enabled ? 1 : 0.5
            activeFocusOnTab: rec.enabled
            objectName: "recordrow:" + entry.index
            Keys.onPressed: event => {
                if (!rec.enabled) return
                if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Up) {
                    rec.moveBy(entry.index, -1)
                    event.accepted = true
                } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Down) {
                    rec.moveBy(entry.index, 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up && entry.index > 0) {
                    rec.focusRow(entry.index - 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    rec.focusRow(entry.index + 1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    rec.removeAt(entry.index)
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    rec.openEdit(entry.index)
                    event.accepted = true
                }
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: (entry.index + 1) + ". " + entry.name

            Column {
                id: labelCol
                anchors.left: parent.left
                anchors.leftMargin: Theme.pad
                anchors.right: buttons.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.pixelSize: Theme.fs
                    font.family: Theme.fam(text, Theme.families)
                    text: (entry.index + 1) + ".  " + entry.name
                }
                Text {
                    visible: text !== ""
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: Theme.fs - 2
                    font.family: Theme.fam(text, Theme.families)
                    text: rec.detailOf(entry.row)
                }
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Button {
                    objectName: "recordup:" + entry.index
                    label: "↑"
                    accessibleName: I18n.fmt("settings.records.up", { item: entry.name })
                    enabled: rec.enabled && entry.index > 0
                    onClicked: rec.moveBy(entry.index, -1)
                }
                Button {
                    objectName: "recorddown:" + entry.index
                    label: "↓"
                    accessibleName: I18n.fmt("settings.records.down", { item: entry.name })
                    enabled: rec.enabled && entry.index < rec.items.length - 1
                    onClicked: rec.moveBy(entry.index, 1)
                }
                Button {
                    objectName: "recordedit:" + entry.index
                    label: I18n.tr("settings.records.edit")
                    accessibleName: I18n.fmt("settings.records.edit_for", { item: entry.name })
                    enabled: rec.enabled
                    onClicked: rec.openEdit(entry.index)
                }
                Button {
                    objectName: "recordremove:" + entry.index
                    label: "×"
                    accessibleName: I18n.fmt("settings.records.remove", { item: entry.name })
                    enabled: rec.enabled
                    onClicked: rec.removeAt(entry.index)
                }
            }
            FocusRing {
                anchors.fill: parent
                shown: entry.activeFocus
                corner: entry.radius
            }
        }
    }

    // Nothing yet: say so, and offer the first one.
    Text {
        visible: rec.items.length === 0 && rec.formRow < 0
        width: rec.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.records.empty")
    }
    Button {
        id: addButton
        objectName: "recordadd"
        visible: rec.formRow < 0
        label: I18n.tr("settings.records.add")
        accessibleName: I18n.tr("settings.records.add")
        enabled: rec.enabled
        onClicked: rec.openAdd()
    }

    // The add and edit form: one control per declared field, the refusal under the field it names.
    Rectangle {
        id: form
        visible: rec.formRow >= 0
        width: rec.width
        height: formCol.implicitHeight + Theme.pad * 2
        radius: Theme.rSm
        // A field is drawn in containerHigh: the form itself must be a step darker, or an empty field disappears in it.
        color: Theme.container
        border.width: 1
        border.color: Theme.outline
        Column {
            id: formCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.pad
            spacing: Theme.gap / 2
            Text {
                width: parent.width
                color: Theme.fg
                font.pixelSize: Theme.fs
                font.family: Theme.fam(text, Theme.families)
                text: rec.formRow >= rec.items.length ? I18n.tr("settings.records.add_title") : I18n.tr("settings.records.edit_title")
            }
            Repeater {
                id: formRep
                model: rec.formRow >= 0 ? rec.fields : []
                delegate: Column {
                    id: fieldBox
                    required property var modelData
                    required property int index
                    readonly property string key: fieldBox.modelData.key
                    readonly property string kind: fieldBox.modelData.type
                    readonly property string err: rec.fieldError(fieldBox.key)
                    width: formCol.width
                    spacing: 2
                    function focusControl(): void {
                        if (fieldBox.kind === "bool") toggle.forceActiveFocus()
                        else if (fieldBox.kind === "enum") pick.forceActiveFocus()
                        else textField.focusInput()
                    }
                    // The field's name, visible above its control (the control's own label is its accessible name only).
                    Text {
                        width: fieldBox.width
                        color: Theme.dim
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr(fieldBox.modelData.label ?? fieldBox.key)
                    }
                    TextField {
                        id: textField
                        objectName: "recordfield:" + fieldBox.key
                        visible: fieldBox.kind === "string" || fieldBox.kind === "url" || fieldBox.kind === "int"
                        width: Math.min(formCol.width, 360)
                        label: I18n.tr(fieldBox.modelData.label ?? fieldBox.key)
                        value: rec.draftText(fieldBox.key)
                        mono: fieldBox.kind === "url"
                        invalid: fieldBox.err !== ""
                        onTyping: t => rec.setDraft(fieldBox.key, rec.typed(fieldBox.kind, t))
                        onSubmitted: rec.submit()
                        onEscaped: rec.cancelForm()
                    }
                    Select {
                        id: pick
                        objectName: "recordfield:" + fieldBox.key
                        visible: fieldBox.kind === "enum"
                        width: Math.min(formCol.width, 360)
                        label: I18n.tr(fieldBox.modelData.label ?? fieldBox.key)
                        choices: fieldBox.modelData.choices ?? []
                        current: rec.draft[fieldBox.key]
                        placeholder: I18n.tr("settings.records.choose")
                        onPicked: v => rec.setDraft(fieldBox.key, v)
                        onCancelled: rec.cancelForm()
                    }
                    Toggle {
                        id: toggle
                        objectName: "recordfield:" + fieldBox.key
                        visible: fieldBox.kind === "bool"
                        label: I18n.tr(fieldBox.modelData.label ?? fieldBox.key)
                        checked: rec.draft[fieldBox.key] === true
                        onToggled: v => rec.setDraft(fieldBox.key, v)
                    }
                    Text {
                        visible: fieldBox.err !== ""
                        width: fieldBox.width
                        wrapMode: Text.WordWrap
                        color: Theme.error
                        font.pixelSize: Theme.fs - 2
                        font.family: Theme.fam(text, Theme.families)
                        text: "✕ " + fieldBox.err
                    }
                }
            }
            Row {
                spacing: Theme.gap
                Button {
                    objectName: "recordsave"
                    primary: true
                    label: I18n.tr("settings.records.save")
                    enabled: rec.enabled
                    onClicked: rec.submit()
                }
                Button {
                    objectName: "recordcancel"
                    label: I18n.tr("settings.records.cancel")
                    onClicked: rec.cancelForm()
                }
            }
            Text {
                width: formCol.width
                wrapMode: Text.WordWrap
                color: Theme.dim
                font.pixelSize: Theme.fs - 2
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("settings.records.hint")
            }
        }
    }
}
