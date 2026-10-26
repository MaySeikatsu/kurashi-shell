import QtQuick
import "../../core"
import "../../surfaces" as S
import ".."

// Module `quick`: the quick settings button (K24) — or, with `sidebar.from_bar`, the right sidebar's on this output (W29).
// Its open state is runtime.ui's (`panel` = quick, or the right sidebar open here); a click toggles it.
ModuleBase {
    id: m
    S.BarConfig { id: cfg; screen: m.screen }
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    readonly property bool open: cfg.sidebarFromBar
        ? ui.sidebar === "right" && (!ui.sidebar_output || ui.sidebar_output === m.output)
        : ui.panel === "quick"
    width: q.width
    height: q.height
    slotHeights: [thickness]
    function geo() { return [["quick", m]] }
    QuickButton {
        id: q
        open: m.open
        onClicked: {
            if (cfg.sidebarFromBar) Store.act("sidebar.toggle", {side: "right", output: m.output})
            else Store.act("quick.toggle")
        }
    }
}
