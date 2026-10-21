import Quickshell
import QtQuick
import "../core"

// The bar of one output as the config document has it (bar.enabled, bar.edge). The lookup is the
// one settings/core/Store.qml prov() uses: an output's own entry wins over the global value, so the
// shell shows what the daemon has in effect. Overlays take their clearance from here.
Scope {
    id: cfg

    // The output this is about (a PanelWindow's screen); null until the first screen is known.
    property var screen: null

    Watch { doc: "config" }

    // The config document as last copied out of Store. The copy is taken on the next event-loop
    // turn after the document itself changed, never inside the change: a Watch that unsubscribes
    // while the change is still being applied calls Store.setDoc again, and a binding on Store.docs
    // would re-enter itself (measured: "Binding loop detected for property config"). Store builds a
    // new object for every snapshot and patch, so identity tells a change; other documents cost one
    // comparison.
    property var config: ({})
    property var copied: undefined
    function refresh() {
        var c = Store.docs["config"]
        if (c === copied) return
        copied = c
        config = c || ({})
    }
    Connections {
        target: Store
        function onDocsChanged() { if (Store.docs["config"] !== cfg.copied) Qt.callLater(cfg.refresh) }
    }
    Component.onCompleted: refresh()

    function entry(key) {
        var c = config
        var out = screen ? screen.name : ""
        if (out !== "" && c.outputs && c.outputs[out] && c.outputs[out][key] !== undefined)
            return c.outputs[out][key]
        return c.values ? c.values[key] : undefined
    }
    function valueOf(key, dflt) {
        var p = entry(key)
        return p && p.value !== undefined ? p.value : dflt
    }

    // Schema defaults until the daemon says otherwise: a bar, on top. An unknown edge reads as top.
    readonly property bool enabled: valueOf("bar.enabled", true) === true
    readonly property string edge: {
        var e = valueOf("bar.edge", "top")
        return e === "bottom" || e === "left" || e === "right" ? e : "top"
    }
    readonly property bool atTop: enabled && edge === "top"
    readonly property bool atBottom: enabled && edge === "bottom"
    readonly property bool atRight: enabled && edge === "right"
    readonly property bool vertical: enabled && (edge === "left" || edge === "right")
    // W29 `sidebar.from_bar`: the quick settings button opens the right sidebar instead of the quick card.
    readonly property bool sidebarFromBar: valueOf("sidebar.from_bar", false) === true

    // Clearance for something that hugs an edge: past the bar when this output's bar sits there,
    // else the screen-edge margin.
    readonly property int topInset: atTop ? Theme.barH + 4 : Theme.gap
    readonly property int bottomInset: atBottom ? Theme.barH + 4 : Theme.gap
    readonly property int rightInset: atRight ? Theme.barH + 4 : Theme.gap
}
