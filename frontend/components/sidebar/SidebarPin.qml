import QtQuick
import Quickshell
import "../../core"
import "../island"
import "../../surfaces" as S

// The sidebar's pin (session 20, K84): kept open while pinned (`sidebar.<side>.pinned`; the daemon lays it out as
// "always shown"), back to the chosen visibility when unpinned. In the header's button row when the header tops the
// column, else in a row of its own at the column's top (Sidebar.qml).
// B47: a pin belongs to one output. It reads that output's value (its own slot in the config document, else the global
// one: the daemon's rule) and writes its own slot with `set` (never `reset`: a reset would fall back to a global pin), so
// a pin holds on its monitor only. `outName` is the sidebar's output; a pin built inside another part of the sidebar (the
// header's) takes the nearest parent that names one, when it is made. Without any, the global slot as before.
KeyButton {
    id: pin
    property string sidebarSide: "right"
    property string outName: ""
    S.BarConfig { id: cfg; screen: null }
    readonly property string key: "sidebar." + sidebarSide + ".pinned"
    readonly property bool pinned: {
        var c = cfg.config || ({})
        var own = outName !== "" && c.outputs && c.outputs[outName] ? c.outputs[outName][key] : undefined
        var e = own !== undefined ? own : (c.values ? c.values[key] : undefined)
        return !!e && e.value === true
    }
    objectName: "sidebar-pin-" + sidebarSide
    icon: "push_pin"
    glyph: "⌖"
    side: 32
    primary: pinned
    a11y: I18n.tr(pinned ? "sidebar.unpin" : "sidebar.pin")
    // The output of the nearest parent that names one (the header's pin is made inside the column).
    function ownerOutput() {
        var p = pin.parent
        while (p) {
            if (p.outName !== undefined && String(p.outName) !== "") return String(p.outName)
            p = p.parent
        }
        return ""
    }
    // Test only (KURASHI_SIDEBAR_GEOMETRY=1, frontend/test-sidebars.sh pages part): where the pin is in its window and what
    // it reads, so the test can click it on its output.
    readonly property bool geometryLog: Quickshell.env("KURASHI_SIDEBAR_GEOMETRY") === "1"
    function logPin() {
        if (!geometryLog) return
        var p = pin.mapToItem(null, 0, 0)
        console.log("sidebar-pin " + outName + " " + sidebarSide + " " + Math.round(p.x) + " " + Math.round(p.y) + " "
            + Math.round(width) + " " + Math.round(height) + " pinned " + pinned)
    }
    onXChanged: logPin()
    onYChanged: logPin()
    onPinnedChanged: logPin()
    Component.onCompleted: {
        if (outName === "") outName = ownerOutput()
        logPin()
    }
    onClicked: {
        var op = { set: key, value: !pinned }
        if (outName !== "") op.output = outName
        Store.apply([op])
    }
}
