import QtQuick
import qs.core
import qs.components
import ".."
import "../Tasks.js" as T

// The note on the desk (K46, docs/ux/tasks.md "Design"): its first lines, Markdown marks dropped. A click opens the panel
// on its note tab (the desk has no keyboard focus, K43). Height 0 while the note is empty, missing or not loaded: the card
// says nothing then (MODS.md, desk cards). A note that cannot be read names why.
Item {
    // Handed in by ModLoader (K26 loader contract).
    required property var store
    required property var theme
    required property var i18n
    id: nc

    // The card lives only while the desk is shown (its ModLoader is gated on that, Ma), so it watches for its lifetime:
    // the desk hides a card of height 0, and a watch gated on visibility would never see the snapshot that shows it.
    Watch { doc: "mod.tasks" }

    readonly property var n: (Store.docs["mod.tasks"] || {}).notes || ({})
    readonly property bool failed: n.state === "error"
    readonly property var lines: T.noteLines(n.text, 6)
    // Something to say: lines of text, or why the note cannot be read.
    readonly property bool wanted: failed || lines.length > 0

    implicitHeight: wanted ? card.height : 0

    DeskCard {
        id: card
        width: nc.width
        visible: nc.wanted
        Column {
            width: parent.width
            spacing: Theme.xs
            Text {
                color: Theme.dim
                font.pixelSize: Theme.fsCaption
                font.weight: Theme.wBold
                font.letterSpacing: 1
                font.capitalization: Font.AllUppercase
                font.family: Theme.fam(text, Theme.families)
                text: I18n.tr("mod-tasks.notes.title")
            }
            Text {
                visible: nc.failed
                width: parent.width
                wrapMode: Text.Wrap
                color: Theme.error
                font.pixelSize: Theme.fs - 1
                font.family: Theme.fam(text, Theme.families)
                text: nc.failed ? I18n.tr(nc.n.reason || "mod-tasks.error.read") : ""
            }
            Repeater {
                model: nc.failed ? [] : nc.lines
                delegate: Text {
                    required property var modelData
                    required property int index
                    width: parent.width
                    elide: Text.ElideRight
                    color: index === 0 ? Theme.fg : Theme.dim
                    font.pixelSize: index === 0 ? Theme.fs + 1 : Theme.fs - 1
                    font.weight: index === 0 ? Theme.wBold : Theme.wRegular
                    font.family: Theme.fam(text, Theme.families)
                    text: modelData
                }
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: I18n.tr("mod-tasks.notes.open")
    }
    MouseArea {
        anchors.fill: parent
        enabled: nc.wanted
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            T.intent = "notes"
            Store.act("mod.panel.open", { id: "tasks", panel: "tasks" })
        }
    }
}
