import QtQuick
import Quickshell
import qs.core
import qs.components
import "Tasks.js" as T

// Panel of the tasks mod (K46, docs/ux/tasks.md "Design"). The Stage card hosts it and draws the frame. Two tabs: the
// tasks (add field on top, the list grouped by its Markdown sections, edit in place, remove, clear done, the file's path
// in the footer) and the note (one text area that saves 600 ms after the last key, on Escape and when it loses focus).
// Every value is the daemon's; every change is an action, answered with an i18n key when refused.
Item {
    // Handed in by ModLoader (K26 loader contract; the core singletons are imported too).
    required property var store
    required property var theme
    required property var i18n
    id: p

    // Visible = open: the documents are subscribed only while the panel can be seen (Ma).
    property bool live: visible
    Watch { doc: "mod.tasks"; active: p.live }
    Watch { doc: "svc.clock"; active: p.live }

    property int cardWidth: 400
    width: parent ? parent.width : cardWidth
    implicitHeight: body.implicitHeight

    readonly property var d: Store.docs["mod.tasks"] || ({})
    readonly property bool loaded: Store.docs["mod.tasks"] !== undefined && d.state !== undefined
    readonly property bool failed: d.state === "error"
    readonly property bool readOnly: d.reason === "mod-tasks.read_only"
    readonly property var tasks: d.tasks || []
    readonly property var notes: d.notes || ({})
    readonly property string today: (Store.docs["svc.clock"] || {}).date || ""
    readonly property string locale: (Store.docs["i18n"] || {}).locale || "en"
    readonly property string home: Quickshell.env("HOME") || ""

    property string tab: "tasks"
    // What the last refused action said (an i18n key), shown under the add field; cleared by the next success.
    property string errorKey: ""
    // The row being edited in place (its id), or "".
    property string editing: ""

    Accessible.role: Accessible.Pane
    Accessible.name: I18n.tr("mod-tasks.panel.title")

    Component.onCompleted: {
        var want = T.intent
        T.intent = ""
        if (want === "notes") p.tab = "notes"
        Qt.callLater(function () {
            if (p.tab === "notes") noteEdit.forceActiveFocus()
            else if (want === "add") addField.input.forceActiveFocus()
        })
    }

    function act(name, args, then) {
        Store.act(name, args, function (done, err) {
            if (err) p.errorKey = err.msg || "mod-tasks.error.write"
            else p.errorKey = ""
            if (then) then(done, err)
        })
    }
    function add() {
        var text = addField.text.trim()
        if (text === "") return
        p.act("tasks.add", { text: text }, function (done, err) { if (!err) addField.text = "" })
    }

    component Caption: Text {
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.weight: Theme.wBold
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
        font.family: Theme.fam(text, Theme.families)
    }
    component Line: Text {
        color: Theme.dim
        font.pixelSize: Theme.fsCaption
        font.family: Theme.fam(text, Theme.families)
    }
    // A tab of the header: a flat label with the accent underline while chosen.
    component Tab: Item {
        id: tb
        property string key: ""
        property string label: ""
        readonly property bool chosen: p.tab === key
        implicitWidth: tl.implicitWidth + 2 * Theme.gap
        implicitHeight: Theme.controlH
        activeFocusOnTab: true
        Keys.onSpacePressed: p.tab = tb.key
        Keys.onReturnPressed: p.tab = tb.key
        Accessible.role: Accessible.PageTab
        Accessible.name: tb.label
        Accessible.selected: tb.chosen
        Text {
            id: tl
            anchors.centerIn: parent
            color: tb.chosen ? Theme.fg : Theme.dim
            font.pixelSize: Theme.fsLabel
            font.weight: tb.chosen ? Theme.wBold : Theme.wMedium
            font.family: Theme.fam(text, Theme.families)
            text: tb.label
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: tl.implicitWidth
            height: 3
            radius: 1.5
            color: Theme.accent
            visible: tb.chosen
        }
        MouseArea { anchors.fill: parent; onClicked: p.tab = tb.key }
        FocusRing { anchors.fill: parent; shown: tb.activeFocus; corner: Theme.rSm }
    }
    // A one-line text field on the surface colour (the add field, the in-place edit).
    component Field: Rectangle {
        id: fr
        property alias input: ti
        property alias text: ti.text
        property string hint: ""
        signal accepted()
        signal cancelled()
        height: Theme.controlH
        radius: Theme.keycap ? Theme.rFull : Theme.rSm
        color: Theme.surface
        border.width: ti.activeFocus ? Math.max(1, Theme.outlineW) : 1
        border.color: ti.activeFocus ? Theme.focusRing : Theme.outline
        TextInput {
            id: ti
            anchors.fill: parent
            anchors.leftMargin: Theme.pad
            anchors.rightMargin: Theme.pad
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Theme.fg
            selectionColor: Theme.selected
            selectedTextColor: Theme.fgOnSelected
            font.pixelSize: Theme.fs
            font.family: Theme.fam(text, Theme.families)
            maximumLength: 500
            Keys.onReturnPressed: fr.accepted()
            Keys.onEnterPressed: fr.accepted()
            Keys.onEscapePressed: function (e) { fr.cancelled(); e.accepted = true }
            Accessible.role: Accessible.EditableText
            Accessible.name: fr.hint
        }
        Text {
            anchors.fill: ti
            verticalAlignment: Text.AlignVCenter
            visible: ti.text === "" && !ti.preeditText
            color: Theme.dim
            font: ti.font
            elide: Text.ElideRight
            text: fr.hint
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onPressed: function (m) { ti.forceActiveFocus(); m.accepted = false } }
    }

    Column {
        id: body
        width: parent.width
        spacing: Theme.gap

        // ---- header: the title and the tabs ----
        Row {
            width: parent.width
            spacing: Theme.xs
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - tabs.width - parent.spacing
                elide: Text.ElideRight
                color: Theme.fg
                font.pixelSize: Theme.fsTitle
                font.weight: Theme.wBold
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("mod-tasks.panel.title")
            }
            Row {
                id: tabs
                anchors.verticalCenter: parent.verticalCenter
                Tab { key: "tasks"; label: I18n.tr("mod-tasks.tab.tasks") }
                Tab { key: "notes"; label: I18n.tr("mod-tasks.tab.notes") }
            }
        }

        Line {
            visible: !p.loaded
            text: I18n.tr("mod-tasks.loading")
        }

        // ================= tasks =================
        Column {
            visible: p.loaded && p.tab === "tasks"
            width: parent.width
            spacing: Theme.gap

            Text {
                visible: p.failed || p.readOnly
                width: parent.width
                wrapMode: Text.Wrap
                color: p.failed ? Theme.error : Theme.dim
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: (p.failed || p.readOnly) ? I18n.tr(p.d.reason || "mod-tasks.error.read") : ""
            }

            Row {
                visible: !p.failed && !p.readOnly
                width: parent.width
                spacing: Theme.xs
                Field {
                    id: addField
                    width: parent.width - addBtn.width - parent.spacing
                    hint: I18n.tr("mod-tasks.add.hint")
                    onAccepted: p.add()
                    onCancelled: { addField.text = ""; addField.input.focus = false }
                }
                IconButton {
                    id: addBtn
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "add"; glyph: "+"
                    a11y: I18n.tr("mod-tasks.add")
                    lit: addField.text.trim() !== ""
                    enabled: addField.text.trim() !== ""
                    onClicked: p.add()
                }
            }
            Text {
                visible: p.errorKey !== ""
                width: parent.width
                wrapMode: Text.Wrap
                color: Theme.error
                font.pixelSize: Theme.fsCaption
                font.family: Theme.fam(text, Theme.families)
                text: p.errorKey !== "" ? I18n.tr(p.errorKey) : ""
            }

            // Empty: nothing in the list (a missing file says that adding creates it).
            Row {
                visible: !p.failed && p.tasks.length === 0
                spacing: Theme.gap
                topPadding: Theme.pad
                bottomPadding: Theme.pad
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "task_alt"; glyph: "✓"
                    size: 32
                    color: Theme.secondary
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        color: Theme.fg
                        font.pixelSize: Theme.fs + 1
                        font.weight: Theme.wBold
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("mod-tasks.empty")
                    }
                    Line {
                        visible: p.d.state === "missing"
                        text: I18n.tr("mod-tasks.missing.hint")
                    }
                }
            }

            // The list, in file order, under its sections; it scrolls past ~10 rows.
            Flickable {
                id: listView
                visible: !p.failed && p.tasks.length > 0
                width: parent.width
                height: Math.min(list.implicitHeight, 420)
                contentHeight: list.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Column {
                    id: list
                    width: listView.width
                    Repeater {
                        model: p.tasks
                        delegate: Column {
                            id: entry
                            required property var modelData
                            required property int index
                            readonly property var t: modelData
                            readonly property bool header: (t.section || "") !== ""
                                && (index === 0 || (p.tasks[index - 1].section || "") !== t.section)
                            readonly property bool editingThis: p.editing === t.id
                            width: list.width
                            Caption {
                                visible: entry.header
                                topPadding: entry.index === 0 ? 0 : Theme.gap
                                bottomPadding: Theme.xs
                                width: parent.width
                                elide: Text.ElideRight
                                text: entry.t.section || ""
                            }
                            Item {
                                id: row
                                width: parent.width
                                height: Math.max(36, (entry.editingThis ? editField.height : txt.implicitHeight) + 10)
                                activeFocusOnTab: true
                                Accessible.role: Accessible.ListItem
                                Accessible.name: entry.t.text + (entry.t.done ? ", " + I18n.tr("mod-tasks.a11y.is_done") : "")
                                    + (entry.t.due ? ", " + T.dueLabel(I18n.tr, entry.t.due, p.today, p.locale) : "")
                                Keys.onSpacePressed: if (!p.readOnly) p.act("tasks.toggle", { id: entry.t.id })
                                Keys.onReturnPressed: if (!p.readOnly) p.editing = entry.t.id
                                Keys.onPressed: function (e) {
                                    if (p.readOnly) return
                                    if (e.key === Qt.Key_F2) { p.editing = entry.t.id; e.accepted = true }
                                    else if (e.key === Qt.Key_Delete) { p.act("tasks.remove", { id: entry.t.id }); e.accepted = true }
                                }
                                HoverHandler { id: rowHover }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.rSm
                                    color: Theme.containerHigh
                                    visible: rowHover.hovered || row.activeFocus
                                    opacity: 0.6
                                }
                                Check {
                                    id: box
                                    x: Theme.xs
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: entry.t.done === true
                                    enabled: !p.readOnly
                                    a11y: T.fill(I18n.tr(entry.t.done ? "mod-tasks.a11y.undone" : "mod-tasks.a11y.done"), { text: entry.t.text })
                                    onToggled: p.act("tasks.toggle", { id: entry.t.id })
                                }
                                Text {
                                    id: txt
                                    visible: !entry.editingThis
                                    anchors.left: box.right
                                    anchors.leftMargin: Theme.gap
                                    anchors.right: marks.left
                                    anchors.rightMargin: Theme.xs
                                    anchors.verticalCenter: parent.verticalCenter
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    color: entry.t.done ? Theme.dim : Theme.fg
                                    font.pixelSize: Theme.fs
                                    font.strikeout: entry.t.done === true
                                    font.family: Theme.fam(text, Theme.families)
                                    text: entry.t.text
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !p.readOnly
                                        onDoubleClicked: p.editing = entry.t.id
                                    }
                                }
                                Field {
                                    id: editField
                                    visible: entry.editingThis
                                    anchors.left: box.right
                                    anchors.leftMargin: Theme.gap
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.xs
                                    anchors.verticalCenter: parent.verticalCenter
                                    hint: I18n.tr("mod-tasks.edit.hint")
                                    onVisibleChanged: if (visible) { text = entry.t.text; input.selectAll(); input.forceActiveFocus() }
                                    onAccepted: {
                                        var v = text.trim()
                                        var id = entry.t.id
                                        p.editing = ""
                                        if (v !== "" && v !== entry.t.text) p.act("tasks.edit", { id: id, text: v })
                                        row.forceActiveFocus()
                                    }
                                    onCancelled: { p.editing = ""; row.forceActiveFocus() }
                                }
                                Row {
                                    id: marks
                                    visible: !entry.editingThis
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.xs
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.xs
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: text !== "" && !entry.t.done
                                        color: entry.t.priority === 1 ? Theme.error : entry.t.priority === 2 ? Theme.warning : Theme.dim
                                        font.pixelSize: Theme.fs
                                        font.weight: Font.Black
                                        font.family: Theme.fam(text, Theme.families)
                                        text: T.priorityMark(entry.t.priority)
                                    }
                                    Chip {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: !!entry.t.due
                                        text: entry.t.due ? T.dueLabel(I18n.tr, entry.t.due, p.today, p.locale) : ""
                                        fg: T.isLate(entry.t, p.today) ? Theme.error
                                            : T.daysTo(entry.t.due, p.today) === 0 ? Theme.accent : Theme.dim
                                    }
                                    IconButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        icon: "close"; glyph: "×"
                                        a11y: T.fill(I18n.tr("mod-tasks.a11y.remove"), { text: entry.t.text })
                                        opacity: rowHover.hovered || row.activeFocus || activeFocus ? 1 : 0
                                        enabled: !p.readOnly
                                        onClicked: p.act("tasks.remove", { id: entry.t.id })
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- footer: the counts, clear done, where the file lives ----
            Rectangle { width: parent.width; height: 1; color: Theme.outline; visible: !p.failed }
            Item {
                visible: !p.failed
                width: parent.width
                height: clear.height
                Line {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    text: T.fill(I18n.tr("mod-tasks.counts"), { open: p.d.open || 0, done: p.d.done || 0 })
                }
                Button {
                    id: clear
                    anchors.right: parent.right
                    label: I18n.tr("mod-tasks.clear_done")
                    enabled: !p.readOnly && (p.d.done || 0) > 0
                    onClicked: p.act("tasks.clear_done", {})
                }
            }
            Line {
                width: parent.width
                elide: Text.ElideMiddle
                text: T.fill(I18n.tr("mod-tasks.file"), { path: T.shortPath(p.d.file, p.home) })
            }
        }

        // ================= note =================
        Column {
            visible: p.loaded && p.tab === "notes"
            width: parent.width
            spacing: Theme.gap

            property string status: ""   // "", "saving", "saved", or an i18n key of a refusal
            id: notePane
            readonly property bool noteFailed: p.notes.state === "error"
            property bool dirty: false
            readonly property string docText: p.notes.text || ""
            // The note follows the file while it is not being edited (an edit elsewhere shows up here).
            onDocTextChanged: if (!notePane.dirty && !noteEdit.activeFocus) noteEdit.text = notePane.docText
            Component.onCompleted: noteEdit.text = notePane.docText
            function save() {
                if (!notePane.dirty) return
                var text = noteEdit.text
                notePane.status = "saving"
                Store.act("tasks.notes.set", { text: text }, function (done, err) {
                    if (err) { notePane.status = err.msg || "mod-tasks.error.write"; return }
                    if (noteEdit.text === text) notePane.dirty = false
                    notePane.status = "saved"
                })
            }
            Timer { id: debounce; interval: 600; onTriggered: notePane.save() }

            Text {
                visible: notePane.noteFailed
                width: parent.width
                wrapMode: Text.Wrap
                color: Theme.error
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: notePane.noteFailed ? I18n.tr(p.notes.reason || "mod-tasks.error.read") : ""
            }
            Rectangle {
                visible: !notePane.noteFailed
                width: parent.width
                height: 300
                radius: Theme.rSm
                color: Theme.surface
                border.width: noteEdit.activeFocus ? Math.max(1, Theme.outlineW) : 1
                border.color: noteEdit.activeFocus ? Theme.focusRing : Theme.outline
                Flickable {
                    id: noteFlick
                    anchors.fill: parent
                    anchors.margins: Theme.pad
                    contentHeight: noteEdit.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    function follow(r) {
                        if (contentY >= r.y) contentY = r.y
                        else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
                    }
                    TextEdit {
                        id: noteEdit
                        width: noteFlick.width
                        wrapMode: TextEdit.Wrap
                        color: Theme.fg
                        selectionColor: Theme.selected
                        selectedTextColor: Theme.fgOnSelected
                        font.pixelSize: Theme.fs
                        font.family: Theme.fam(text, Theme.families)
                        textFormat: TextEdit.PlainText
                        onCursorRectangleChanged: noteFlick.follow(cursorRectangle)
                        onTextChanged: if (activeFocus) { notePane.dirty = true; notePane.status = ""; debounce.restart() }
                        onActiveFocusChanged: if (!activeFocus) { debounce.stop(); notePane.save() }
                        Keys.onEscapePressed: function (e) { debounce.stop(); notePane.save(); noteEdit.focus = false; e.accepted = true }
                        Accessible.role: Accessible.EditableText
                        Accessible.name: I18n.tr("mod-tasks.notes.title")
                    }
                    Text {
                        visible: noteEdit.text === ""
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Theme.dim
                        font: noteEdit.font
                        text: I18n.tr("mod-tasks.notes.hint")
                    }
                }
            }
            Item {
                width: parent.width
                height: Math.max(noteState.implicitHeight, notePath.implicitHeight)
                Line {
                    id: noteState
                    anchors.right: parent.right
                    color: notePane.status !== "" && notePane.status !== "saving" && notePane.status !== "saved" ? Theme.error : Theme.dim
                    text: notePane.status === "saving" ? I18n.tr("mod-tasks.notes.saving")
                        : notePane.status === "saved" ? I18n.tr("mod-tasks.notes.saved")
                        : notePane.status !== "" ? I18n.tr(notePane.status) : ""
                }
                Line {
                    id: notePath
                    anchors.left: parent.left
                    width: parent.width - noteState.width - Theme.gap
                    elide: Text.ElideMiddle
                    text: T.fill(I18n.tr("mod-tasks.file"), { path: T.shortPath(p.notes.file, p.home) })
                }
            }
        }
    }
}
