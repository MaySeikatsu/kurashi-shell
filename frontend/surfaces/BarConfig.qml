import Quickshell
import QtQuick
import "../core"

// The bar of one output as the config document has it (`edges.<edge>.bar`, K71). The lookup is the
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

    // Schema v3 (K71): a bar per edge (`edges.<edge>.bar`). The shell draws one bar for now: the first edge that has one,
    // top, bottom, left, right; none, no bar. Schema defaults until the daemon says otherwise: a bar, on top.
    readonly property string barEdge: {
        var order = ["top", "bottom", "left", "right"]
        for (var i = 0; i < order.length; i++)
            if (valueOf("edges." + order[i] + ".bar", order[i] === "top") === true) return order[i]
        return ""
    }
    readonly property bool enabled: barEdge !== ""
    readonly property string edge: barEdge !== "" ? barEdge : "top"
    readonly property bool atTop: enabled && edge === "top"
    readonly property bool atBottom: enabled && edge === "bottom"
    readonly property bool atRight: enabled && edge === "right"
    readonly property bool vertical: enabled && (edge === "left" || edge === "right")
    // W29 `sidebar.from_bar`: the quick settings button opens the right sidebar instead of the quick card.
    readonly property bool sidebarFromBar: valueOf("sidebar.from_bar", false) === true
    // I154: a button at each end of the bar opens that side's sidebar; the left one only while the left sidebar has tabs
    // configured (the daemon refuses it otherwise). K71: the buttons are the modules `sidebar_left` / `sidebar_right` in
    // the bar's zones (`sidebar.bar_buttons = false` migrated to zones without them).
    function zoneHas(id) {
        var zones = ["start", "center", "end"]
        // The top edge's schema defaults until the daemon says otherwise (the buttons at both ends).
        var top = [["sidebar_left"], [], ["sidebar_right"]]
        for (var i = 0; i < zones.length; i++) {
            var z = valueOf("edges." + edge + "." + zones[i], edge === "top" ? top[i] : [])
            if (Array.isArray(z) && z.indexOf(id) >= 0) return true
        }
        return false
    }
    readonly property bool sidebarButtons: zoneHas("sidebar_left") || zoneHas("sidebar_right")
    readonly property bool leftSidebarTabs: {
        var t = valueOf("sidebar.left.sections", [])
        return Array.isArray(t) && t.length > 0
    }

    // Clearance for something that hugs an edge: past the bar when this output's bar sits there,
    // else the screen-edge margin.
    readonly property int topInset: atTop ? Theme.barH + 4 : Theme.gap
    readonly property int bottomInset: atBottom ? Theme.barH + 4 : Theme.gap
    readonly property int rightInset: atRight ? Theme.barH + 4 : Theme.gap
}
