import QtQuick
import "../core"

// Shōjiki (rule 2): where the effective value comes from. `prov` is {source:{kind,name?}, forced_by?}.
// Forced values are drawn with the accent edge: the user does not control them.
Item {
    id: p
    property var prov: ({})
    readonly property bool forced: prov !== undefined && prov.forced_by !== undefined && prov.forced_by !== null
    readonly property string kind: (prov && prov.source) ? (prov.source.kind || "") : ""
    readonly property string name: (prov && prov.source && prov.source.name) ? prov.source.name : ""
    readonly property string label: {
        if (kind === "") return ""
        var base = I18n.tr("settings.source." + kind)
        return name !== "" ? base + ": " + name : base
    }

    implicitWidth: chip.implicitWidth
    implicitHeight: chip.implicitHeight

    Chip {
        id: chip
        text: p.label
        edge: p.forced ? Theme.accent : (p.kind === "user" ? Theme.fg : Theme.outline)
        fg: p.kind === "user" ? Theme.fg : Theme.dim
    }
}
