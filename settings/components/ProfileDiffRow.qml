import QtQuick
import "../core"

// One changed setting of a profile review (UX brief, settings 6): what it is now and the layer that sets it, what the
// profile sets it to, and "your change replaced" where a value of yours is what the profile overrides. The values and
// the layers are the daemon's answer (profile.preview, profile.import); this row only lays them out.
Flow {
    id: r
    property var entry: ({})
    readonly property var before: entry.before ?? null
    readonly property var after: entry.after ?? null
    readonly property bool replacesUser: !!before && !!before.source && before.source.kind === "user"
    readonly property string name: {
        var k = entry.key || ""
        var label = Store.labelOf(k)
        return (label ? I18n.tr(label) : k) + (entry.output ? " (" + entry.output + ")" : "")
    }

    spacing: Theme.gap / 2

    Text {
        width: 260
        height: Theme.controlH
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: r.name
    }
    Text {
        height: Theme.controlH
        verticalAlignment: Text.AlignVCenter
        color: Theme.dim
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: r.before ? Store.displayValue(r.before.value) : I18n.tr("settings.ui.not_set")
    }
    ProvenanceChip {
        visible: !!r.before
        prov: r.before ?? ({})
        key: r.entry.key || ""
        output: r.entry.output ?? ""
    }
    Text {
        height: Theme.controlH
        verticalAlignment: Text.AlignVCenter
        color: Theme.dim
        font.pixelSize: Theme.fs
        text: "→"
    }
    Text {
        height: Theme.controlH
        verticalAlignment: Text.AlignVCenter
        color: Theme.fg
        font.pixelSize: Theme.fs
        font.family: Theme.fam(text, Theme.families)
        text: r.after ? Store.displayValue(r.after.value) : I18n.tr("settings.ui.not_set")
    }
    Chip {
        visible: r.replacesUser
        text: I18n.tr("settings.ui.profile_replaced")
        fg: Theme.fg
        bg: Theme.surface
        edge: Theme.accent
    }
}
