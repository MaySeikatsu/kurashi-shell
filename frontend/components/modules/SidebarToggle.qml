import QtQuick
import "../../core"
import "../../surfaces" as S
import ".."

// Modules `sidebar_left` and `sidebar_right` (I154; K71 folded `sidebar.bar_buttons` into the zones): the button that
// opens that side's sidebar on this output (`sidebar.toggle`). The left one is present only while the left sidebar has
// sections (the daemon refuses it otherwise); the right one not while the quick button already opens the right sidebar
// (`sidebar.from_bar`).
ModuleBase {
    id: m
    property string side: "right"
    S.BarConfig { id: cfg; screen: m.screen }
    readonly property var ui: Store.docs["runtime.ui"] || ({})
    present: side === "left" ? cfg.leftSidebarTabs : !cfg.sidebarFromBar
    width: b.width
    height: b.height
    slotHeights: [thickness]
    function geo() { return [["sidebar-" + m.side, m]] }
    SidebarButton {
        id: b
        side: m.side
        open: m.ui.sidebar === m.side && (!m.ui.sidebar_output || m.ui.sidebar_output === m.output)
        onClicked: Store.act("sidebar.toggle", {side: m.side, output: m.output})
    }
}
