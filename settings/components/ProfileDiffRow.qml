import QtQuick
import "../core"

// One changed setting of a profile review (UX brief, settings 6): what it is now and the layer that sets it, what the
// profile sets it to, and "your change replaced" where a value of yours is what the profile overrides. A line whose value
// stays (same_value, I64) says "Now from this profile" instead, in a neutral chip. The values and the layers are the
// daemon's answer (profile.preview, profile.import); this row only lays them out.
Flow {
    id: r
    property var entry: ({})
    readonly property var before: entry.before ?? null
    readonly property var after: entry.after ?? null
    readonly property bool same: entry.same_value === true
    readonly property bool replacesUser: !same && !!before && !!before.source && before.source.kind === "user"
    readonly property string name: {
        var k = entry.key || ""
        var label = Store.labelOf(k)
        return (label ? I18n.tr(label) : k) + (entry.output ? " (" + entry.output + ")" : "")
    }

    spacing: Theme.gap / 2

    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
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
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
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
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
        height: Theme.controlH
        verticalAlignment: Text.AlignVCenter
        color: Theme.dim
        font.pixelSize: Theme.fs
        text: "→"
    }
    Text {
        renderType: Theme.pixelType ? Text.NativeRendering : Text.QtRendering
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
    // Neutral: nothing is replaced, the setting is the same and now comes from the profile (I64 (2)).
    Chip {
        visible: r.same
        text: I18n.tr("settings.ui.profile_now_from")
        fg: Theme.dim
        bg: Theme.surface
        edge: Theme.outline
    }
}
