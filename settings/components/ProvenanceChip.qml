import QtQuick
import QtQuick.Controls
import "../core"

// Shōjiki (rule 2): where the effective value comes from, in words (UX brief: "Kanso profile", "you",
// "Nix: programs.kurashi.settings.theme.palette", "accessibility"). Forced values have the accent edge: the user does not
// control them. Hover or focus shows every layer that sets the key, lowest first, from cfg.explain (cfg.why); the layer in
// effect is marked. The chip takes Tab focus, so the keyboard can read the same stack.
Item {
    id: p
    property var prov: ({})
    property string key: ""
    property string output: ""
    readonly property var src: prov ? prov.source : undefined
    readonly property string kind: src ? (src.kind || "") : ""
    readonly property bool forced: !!prov && prov.forced_by !== undefined && prov.forced_by !== null
    readonly property string label: Store.sourceName(p.key, p.src)
    readonly property var layers: { Store.explained; return Store.explained[p.key + "|" + p.output] || [] }
    readonly property string stack: {
        var out = []
        for (var i = 0; i < p.layers.length; i++) {
            var l = p.layers[i]
            var line = Store.sourceName(p.key, l.source) + ": " + Store.displayValue(l.value)
            if (l.reason) line += " · " + I18n.fmt(l.reason, { name: l.source && l.source.name ? l.source.name : "",
                                                              key: l.source && l.source.name ? l.source.name : "" })
            if (l.active) line += "  ◂ " + I18n.tr("settings.ui.in_effect")
            out.push(line)
        }
        return out.join("\n")
    }

    implicitWidth: chip.implicitWidth
    implicitHeight: chip.implicitHeight
    activeFocusOnTab: p.key !== ""
    Accessible.role: Accessible.StaticText
    Accessible.name: I18n.fmt("settings.ui.source_of", { name: p.label })

    function ask() { if (p.key !== "") Store.explain(p.key, p.output, null) }
    onActiveFocusChanged: if (activeFocus) ask()
    HoverHandler {
        id: hov
        onHoveredChanged: if (hovered) p.ask()
    }
    ToolTip.visible: (hov.hovered || p.activeFocus) && p.stack !== ""
    ToolTip.delay: 200
    ToolTip.text: p.stack

    Chip {
        id: chip
        text: p.label
        edge: p.forced ? Theme.accent : (p.kind === "user" ? Theme.fg : Theme.outline)
        fg: p.kind === "user" ? Theme.fg : Theme.dim
    }
    FocusRing {
        anchors.fill: chip
        anchors.margins: -2
        shown: p.activeFocus
        corner: chip.radius + 2
    }
}
