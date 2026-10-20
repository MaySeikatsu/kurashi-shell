import QtQuick
import qs.core
import qs.components
import ".."
import "../Tasks.js" as T

// The tasks card on the desk (K46, docs/ux/tasks.md "Design"): the open count, up to seven items (open first, then the
// done ones the daemon kept), a checkbox that ticks an item and "+ Add", which opens the panel's add field. The desk has
// no keyboard focus (K43): editing lives in the panel. Height 0 until the first snapshot (nothing to say yet).
// Ma: the document is watched only while the card is visible; nothing animates on its own.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: dc

    // The card lives only while the desk is shown (its ModLoader is gated on that, Ma), so it watches for its lifetime:
    // the desk hides a card of height 0, and a watch gated on visibility would never see the snapshot that shows it.
    Watch { doc: "mod.tasks" }
    Watch { doc: "svc.clock" }

    readonly property var d: Store.docs["mod.tasks"] || ({})
    readonly property bool loaded: Store.docs["mod.tasks"] !== undefined && d.state !== undefined
    readonly property string state_: d.state || ""
    readonly property bool failed: state_ === "error"
    readonly property bool readOnly: d.reason === "mod-tasks.read_only"
    readonly property var rows: T.ordered(d.tasks)
    readonly property int maxRows: 7
    readonly property var shown: rows.slice(0, maxRows)
    readonly property int more: Math.max(0, rows.length - maxRows)
    readonly property string today: (Store.docs["svc.clock"] || {}).date || ""
    readonly property string locale: (Store.docs["i18n"] || {}).locale || "en"

    implicitHeight: loaded ? card.height : 0

    function openPanel(intent) {
        T.intent = intent
        Store.act("mod.panel.open", { id: "tasks", panel: "tasks" })
    }

    DeskCard {
        id: card
        width: dc.width
        visible: dc.loaded
        Column {
            width: parent.width
            spacing: Theme.xs + 2

            // ---- title: the caption and the open count ----
            Item {
                width: parent.width
                height: Math.max(cap.implicitHeight, count.implicitHeight)
                Text {
                    id: cap
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.weight: Theme.wBold
                    font.letterSpacing: 1
                    font.capitalization: Font.AllUppercase
                    font.family: Theme.fam(text, Theme.families)
                    text: I18n.tr("mod-tasks.title")
                }
                Chip {
                    id: count
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !dc.failed
                    text: T.fill(I18n.tr("mod-tasks.open_count"), { n: dc.d.open || 0 })
                    fg: (dc.d.open || 0) > 0 ? Theme.fg : Theme.dim
                }
            }

            // ---- the reason when the file cannot be read ----
            Text {
                visible: dc.failed
                width: parent.width
                wrapMode: Text.Wrap
                color: Theme.error
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: dc.failed ? I18n.tr(dc.d.reason || "mod-tasks.error.read") : ""
            }

            // ---- empty: nothing open and nothing kept ----
            Row {
                visible: !dc.failed && dc.rows.length === 0
                spacing: Theme.gap
                topPadding: Theme.xs
                bottomPadding: Theme.xs
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "task_alt"
                    glyph: "✓"
                    size: 28
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
                    Text {
                        visible: dc.state_ === "missing"
                        color: Theme.dim
                        font.pixelSize: Theme.fsCaption
                        font.family: Theme.fam(text, Theme.families)
                        text: I18n.tr("mod-tasks.missing.hint")
                    }
                }
            }

            // ---- the items ----
            Repeater {
                model: dc.failed ? [] : dc.shown
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool late: T.isLate(modelData, dc.today)
                    width: parent.width
                    height: Math.max(box.height, label.implicitHeight) + 4
                    Check {
                        id: box
                        anchors.verticalCenter: parent.verticalCenter
                        checked: row.modelData.done === true
                        enabled: !dc.readOnly
                        a11y: T.fill(I18n.tr(row.modelData.done ? "mod-tasks.a11y.undone" : "mod-tasks.a11y.done"),
                                     { text: row.modelData.text })
                        onToggled: Store.act("tasks.toggle", { id: row.modelData.id })
                    }
                    Text {
                        id: label
                        anchors.left: box.right
                        anchors.leftMargin: Theme.gap
                        anchors.right: marks.left
                        anchors.rightMargin: marks.width > 0 ? Theme.xs : 0
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        color: row.modelData.done ? Theme.dim : Theme.fg
                        font.pixelSize: Theme.fs
                        font.weight: Theme.wMedium
                        font.strikeout: row.modelData.done === true
                        font.family: Theme.fam(text, Theme.families)
                        text: row.modelData.text
                    }
                    Row {
                        id: marks
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.xs
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: text !== "" && !row.modelData.done
                            color: row.modelData.priority === 1 ? Theme.error
                                : row.modelData.priority === 2 ? Theme.warning : Theme.dim
                            font.pixelSize: Theme.fs
                            font.weight: Font.Black
                            font.family: Theme.fam(text, Theme.families)
                            text: T.priorityMark(row.modelData.priority)
                        }
                        Chip {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!row.modelData.due && !row.modelData.done
                            text: row.modelData.due ? T.dueLabel(I18n.tr, row.modelData.due, dc.today, dc.locale) : ""
                            fg: row.late ? Theme.error : T.daysTo(row.modelData.due, dc.today) === 0 ? Theme.accent : Theme.dim
                        }
                    }
                }
            }

            // ---- more, and the way to add ----
            Item {
                visible: !dc.failed
                width: parent.width
                height: add.height
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: dc.more > 0
                    color: Theme.dim
                    font.pixelSize: Theme.fsCaption
                    font.family: Theme.fam(text, Theme.families)
                    text: T.fill(I18n.tr("mod-tasks.more"), { n: dc.more })
                    MouseArea { anchors.fill: parent; onClicked: dc.openPanel("") }
                }
                Button {
                    id: add
                    anchors.right: parent.right
                    label: I18n.tr("mod-tasks.add")
                    icon: "add"
                    enabled: !dc.readOnly
                    onClicked: dc.openPanel("add")
                }
            }
        }
    }
}
