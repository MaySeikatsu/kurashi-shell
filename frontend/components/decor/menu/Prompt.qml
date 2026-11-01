import QtQuick
import "../../../core"

// Prompt (W53.8, docs/ux/styles.md "terminal"): a menu row as a fuzzy finder's line (fzf, a shell's completion menu):
// the selected row has the `>` pointer in its lead (`[decor] menu.lead`, the room the caller keeps at the row's start),
// bold, in the accent, over a faint band (`menu.fill`; the caller's selection when unset) — no rounded capsule, no
// spring: the pointer jumps with the selection. A separator is a rule of the type's own box-drawing `─` in the outline's
// ink (`menu.separator = line`), a gap with `space`. Roles only (rule 4); static.
MenuRowBase {
    id: row
    readonly property string band: Theme.decor("menu.fill", "")
    readonly property string sep: Theme.decor("menu.separator", "line")
    readonly property real lead: Theme.decor("menu.lead", 0) * Theme.pixelScale
    Rectangle {
        anchors.fill: parent
        visible: row.highlighted && row.enabled && !row.separator
        antialiasing: false
        color: row.band !== "" ? row.band : Theme.selected
    }
    Text {
        visible: row.highlighted && row.enabled && !row.separator
        x: Math.max(2, Math.round((row.lead - implicitWidth) / 2) + 2)
        anchors.verticalCenter: parent.verticalCenter
        text: ">"
        color: Theme.accent
        font.family: Theme.families[0]
        font.pixelSize: Theme.fs + 1
        font.weight: Font.Bold
    }
    Text {
        visible: row.separator && row.sep === "line"
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 4; rightMargin: 4 }
        clip: true
        elide: Text.ElideNone
        wrapMode: Text.NoWrap
        text: "─".repeat(240)
        color: Theme.outline
        font.family: Theme.families[0]
        font.pixelSize: Theme.fs
    }
}
