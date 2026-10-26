import QtQuick
import "../core"

// The preset's draw mode, as its picker (SettingRow.picker: the pills stay in the control column, with the row's provenance and
// Reset under them). The three modes follow in one line (UX brief, docs/ux/layout.md "Design": each mode in words); the row's help
// says the same at length, this line is what a person reads to pick one. It reads and sets its value itself: `rowKey` is bound by
// SettingRow, as every picker's is.
Column {
    id: modes
    property string rowKey: ""
    readonly property var row: { Store.schema; var h = Store.rowOf(modes.rowKey); return h ? h.row : ({}) }
    readonly property var provOf: { Store.config; return Store.prov(modes.rowKey, "") }

    spacing: Theme.gap / 2

    Segmented {
        objectName: "modes:" + modes.rowKey
        width: parent.width
        choices: modes.row.choices ?? []
        current: modes.provOf === undefined ? modes.row.default : modes.provOf.value
        enabled: Store.live
        cancellable: false
        onPicked: v => Store.setValue(modes.rowKey, v, "")
    }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Theme.dim
        font.pixelSize: Theme.fs - 2
        font.family: Theme.fam(text, Theme.families)
        text: I18n.tr("settings.layout.draw_modes")
    }
}
